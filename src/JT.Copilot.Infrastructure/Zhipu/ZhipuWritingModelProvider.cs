using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using JT.Copilot.Application.Abstractions;
using JT.Copilot.Application.Models;

namespace JT.Copilot.Infrastructure.Zhipu;

public sealed class ZhipuWritingModelProvider : IWritingModelProvider
{
    private const string Endpoint =
        "https://open.bigmodel.cn/api/paas/v4/chat/completions";
    private const string FastModel = "glm-4.5-air";
    private const string EditingModel = "glm-4.6";

    private readonly HttpClient _httpClient;
    private readonly IZhipuApiKeyStore _apiKeyStore;

    public ZhipuWritingModelProvider(
        HttpClient httpClient,
        IZhipuApiKeyStore apiKeyStore)
    {
        _httpClient = httpClient;
        _apiKeyStore = apiKeyStore;
    }

    public async Task<WritingGuidance> AnalyzeAsync(
        string transcript,
        WritingGuidance? previousGuidance,
        CancellationToken cancellationToken = default)
    {
        var previousFramework = previousGuidance is null
            ? "无"
            : string.Join("；", previousGuidance.Framework);

        var content = await CompleteJsonAsync(
            "你是实时口述写作教练。只输出JSON，不要解释，不要输出思考过程。"
            + "目标是在用户连续口述时帮助其避免卡壳。"
            + "输出字段：framework字符串数组、next_sentence字符串、directions字符串数组、missing_points字符串数组。"
            + "每项不超过40字，建议必须具体，不要复述整段内容。",
            $"已有框架：{previousFramework}\n当前全文：{ClipTranscript(transcript)}",
            420,
            FastModel,
            0.1,
            cancellationToken).ConfigureAwait(false);

        var result = JsonSerializer.Deserialize<GuidanceDto>(content, JsonOptions)
            ?? throw new InvalidOperationException("智谱返回了空的表达建议。");

        return new WritingGuidance(
            CleanItems(result.Framework),
            result.NextSentence?.Trim() ?? string.Empty,
            CleanItems(result.Directions),
            CleanItems(result.MissingPoints));
    }

    public async Task<string> OptimizeAsync(
        string transcript,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(transcript))
        {
            return string.Empty;
        }

        var content = await CompleteJsonAsync(
            "你是中文文字编辑。只输出JSON，不要解释，不要输出思考过程。"
            + "只修正错别字、同音字、语法、标点、明显重复和不通顺表达，保持原意、专有名词、数字和业务结论。"
            + "不要扩写，不要改变结构。输出字段：optimized_text字符串、changes数组。"
            + "changes数组每项包含original、corrected、type。",
            ClipTranscript(transcript, 24_000),
            2_048,
            EditingModel,
            0.0,
            cancellationToken).ConfigureAwait(false);

        var result = JsonSerializer.Deserialize<OptimizeDto>(content, JsonOptions)
            ?? throw new InvalidOperationException("智谱返回了空的全文优化结果。");

        return result.OptimizedText?.Trim() ?? transcript;
    }

    public async Task<string> OptimizeSegmentsAsync(
        IReadOnlyList<string> transcriptSegments,
        CancellationToken cancellationToken = default)
    {
        if (transcriptSegments.Count == 0)
        {
            return string.Empty;
        }

        var segmentText = string.Join(
            "\n",
            transcriptSegments.Select((segment, index) => $"片段{index + 1}：{segment}"));

        var content = await CompleteJsonAsync(
            "你是中文文字编辑。以下内容是同一段连续口述按时间切分后产生的ASR片段，"
            + "相邻片段可能存在重叠、重复、断句和同音字错误。"
            + "请将这些片段合并为一段完整自然的文字，去除重复，修正错别字、语法和标点。"
            + "只做必要修改，保持原意，保留专有名词、数字和业务结论，不得扩写或添加事实。"
            + "只输出JSON，不要解释，不要输出思考过程。输出字段：optimized_text字符串、changes数组。"
            + "changes数组每项包含original、corrected、type。",
            segmentText,
            3_000,
            EditingModel,
            0.0,
            cancellationToken).ConfigureAwait(false);

        var result = JsonSerializer.Deserialize<OptimizeDto>(content, JsonOptions)
            ?? throw new InvalidOperationException("智谱返回了空的片段合并结果。");

        return result.OptimizedText?.Trim()
            ?? string.Join(string.Empty, transcriptSegments);
    }

    private async Task<string> CompleteJsonAsync(
        string systemPrompt,
        string userPrompt,
        int maxTokens,
        string model,
        double temperature,
        CancellationToken cancellationToken)
    {
        var apiKey = await _apiKeyStore.GetApiKeyAsync(cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            throw new InvalidOperationException("未配置智谱 API Key。");
        }

        var requestBody = new
        {
            model,
            messages = new[]
            {
                new { role = "system", content = systemPrompt },
                new { role = "user", content = userPrompt }
            },
            temperature,
            stream = false,
            max_tokens = maxTokens,
            response_format = new { type = "json_object" },
            thinking = new { type = "disabled" }
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint)
        {
            Content = JsonContent.Create(requestBody)
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);

        using var response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);

        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(
                $"智谱写作分析失败（{(int)response.StatusCode}）：{ExtractErrorMessage(responseBody)}");
        }

        using var document = JsonDocument.Parse(responseBody);
        var content = document.RootElement
            .GetProperty("choices")[0]
            .GetProperty("message")
            .GetProperty("content")
            .GetString();

        if (string.IsNullOrWhiteSpace(content))
        {
            throw new InvalidOperationException("智谱没有返回可解析的内容。");
        }

        return ExtractJsonObject(content);
    }

    private static IReadOnlyList<string> CleanItems(IEnumerable<string>? items)
    {
        return items?
            .Where(item => !string.IsNullOrWhiteSpace(item))
            .Select(item => item.Trim())
            .Distinct(StringComparer.Ordinal)
            .Take(6)
            .ToArray()
            ?? [];
    }

    private static string ClipTranscript(string transcript, int maxLength = 8_000)
    {
        return transcript.Length <= maxLength
            ? transcript
            : transcript[^maxLength..];
    }

    private static string ExtractJsonObject(string content)
    {
        var firstBrace = content.IndexOf('{');
        var lastBrace = content.LastIndexOf('}');
        if (firstBrace < 0 || lastBrace <= firstBrace)
        {
            throw new InvalidOperationException("智谱返回内容不是有效 JSON。");
        }

        return content[firstBrace..(lastBrace + 1)];
    }

    private static string ExtractErrorMessage(string responseBody)
    {
        try
        {
            using var document = JsonDocument.Parse(responseBody);
            if (document.RootElement.TryGetProperty("error", out var error)
                && error.TryGetProperty("message", out var message))
            {
                return message.GetString() ?? "未知错误";
            }
        }
        catch (JsonException)
        {
        }

        return "未知错误";
    }

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private sealed record GuidanceDto(
        IReadOnlyList<string>? Framework,
        [property: JsonPropertyName("next_sentence")]
        string? NextSentence,
        IReadOnlyList<string>? Directions,
        [property: JsonPropertyName("missing_points")]
        IReadOnlyList<string>? MissingPoints);

    private sealed record OptimizeDto(
        [property: JsonPropertyName("optimized_text")]
        string? OptimizedText);
}
