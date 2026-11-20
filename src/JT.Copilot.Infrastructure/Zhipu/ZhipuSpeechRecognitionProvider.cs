using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using JT.Copilot.Application.Abstractions;
using Microsoft.Extensions.Logging;

namespace JT.Copilot.Infrastructure.Zhipu;

public sealed class ZhipuSpeechRecognitionProvider : ISpeechRecognitionProvider
{
    private const string Endpoint =
        "https://open.bigmodel.cn/api/paas/v4/audio/transcriptions";
    private const string Model = "glm-asr-2512";

    private readonly HttpClient _httpClient;
    private readonly IZhipuApiKeyStore _apiKeyStore;
    private readonly ILogger<ZhipuSpeechRecognitionProvider> _logger;

    public ZhipuSpeechRecognitionProvider(
        HttpClient httpClient,
        IZhipuApiKeyStore apiKeyStore,
        ILogger<ZhipuSpeechRecognitionProvider> logger)
    {
        _httpClient = httpClient;
        _apiKeyStore = apiKeyStore;
        _logger = logger;
    }

    public async Task<string> TranscribeAsync(
        ReadOnlyMemory<byte> wavAudio,
        string transcriptContext,
        CancellationToken cancellationToken = default)
    {
        if (wavAudio.IsEmpty)
        {
            return string.Empty;
        }

        var apiKey = await _apiKeyStore.GetApiKeyAsync(cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            throw new InvalidOperationException("未配置智谱 API Key。");
        }

        for (var attempt = 1; attempt <= 2; attempt++)
        {
            try
            {
                using var request = CreateRequest(apiKey, wavAudio, transcriptContext);
                using var response = await _httpClient
                    .SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken)
                    .ConfigureAwait(false);

                var responseBody = await response.Content
                    .ReadAsStringAsync(cancellationToken)
                    .ConfigureAwait(false);

                if (response.IsSuccessStatusCode)
                {
                    return ParseTranscriptionResponse(
                        responseBody,
                        response.Content.Headers.ContentType?.MediaType);
                }

                if (attempt == 1
                    && (response.StatusCode == HttpStatusCode.TooManyRequests
                        || (int)response.StatusCode >= 500))
                {
                    await Task.Delay(TimeSpan.FromMilliseconds(450), cancellationToken).ConfigureAwait(false);
                    continue;
                }

                throw new InvalidOperationException(
                    $"智谱语音识别失败（{(int)response.StatusCode}）：{ExtractErrorMessage(responseBody)}");
            }
            catch (HttpRequestException exception) when (attempt == 1)
            {
                _logger.LogWarning(exception, "Transient Zhipu ASR request failure.");
                await Task.Delay(TimeSpan.FromMilliseconds(450), cancellationToken).ConfigureAwait(false);
            }
        }

        return string.Empty;
    }

    private static HttpRequestMessage CreateRequest(
        string apiKey,
        ReadOnlyMemory<byte> wavAudio,
        string transcriptContext)
    {
        var content = new MultipartFormDataContent();
        content.Add(new StringContent(Model), "model");
        content.Add(new StringContent("true"), "stream");

        if (!string.IsNullOrWhiteSpace(transcriptContext))
        {
            content.Add(new StringContent(transcriptContext[Math.Max(0, transcriptContext.Length - 6_000)..]), "prompt");
        }

        var audioContent = new ByteArrayContent(wavAudio.ToArray());
        audioContent.Headers.ContentType = new MediaTypeHeaderValue("audio/wav");
        content.Add(audioContent, "file", "segment.wav");

        var request = new HttpRequestMessage(HttpMethod.Post, Endpoint)
        {
            Content = content
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        return request;
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

    private static string ParseTranscriptionResponse(
        string responseBody,
        string? mediaType)
    {
        if (mediaType?.Contains("event-stream", StringComparison.OrdinalIgnoreCase) == true
            || responseBody.TrimStart().StartsWith("data:", StringComparison.OrdinalIgnoreCase))
        {
            var completedText = string.Empty;

            foreach (var line in responseBody.Split('\n'))
            {
                var trimmed = line.Trim();
                if (!trimmed.StartsWith("data:", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var payload = trimmed[5..].Trim();
                if (payload.Length == 0 || payload == "[DONE]")
                {
                    continue;
                }

                try
                {
                    using var eventDocument = JsonDocument.Parse(payload);
                    if (eventDocument.RootElement.TryGetProperty("type", out var type)
                        && type.GetString() == "transcript.text.done"
                        && eventDocument.RootElement.TryGetProperty("text", out var text))
                    {
                        completedText = text.GetString()?.Trim() ?? string.Empty;
                    }
                }
                catch (JsonException)
                {
                }
            }

            return completedText;
        }

        using var document = JsonDocument.Parse(responseBody);
        return document.RootElement.TryGetProperty("text", out var textElement)
            ? textElement.GetString()?.Trim() ?? string.Empty
            : string.Empty;
    }
}
