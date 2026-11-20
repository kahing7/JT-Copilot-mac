using System.IO;
using System.Net;
using System.Net.Http;
using System.Text;
using JT.Copilot.Application.Abstractions;
using JT.Copilot.Infrastructure.Security;
using JT.Copilot.Infrastructure.Zhipu;
using Microsoft.Extensions.Logging.Abstractions;

namespace JT.Copilot.IntegrationTests;

public sealed class ZhipuProviderTests
{
    [Fact]
    public async Task SpeechRecognition_ParsesSseCompletedText()
    {
        const string body =
            "data: {\"type\":\"transcript.text.delta\",\"delta\":\"你好\"}\n\n"
            + "data: {\"type\":\"transcript.text.done\",\"text\":\"你好，世界。\"}\n\n"
            + "data: [DONE]\n\n";
        using var httpClient = new HttpClient(new StubHttpMessageHandler(
            _ => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(body, Encoding.UTF8, "text/event-stream")
            }));
        var provider = new ZhipuSpeechRecognitionProvider(
            httpClient,
            new StubApiKeyStore(),
            NullLogger<ZhipuSpeechRecognitionProvider>.Instance);

        var result = await provider.TranscribeAsync(new byte[] { 1, 2, 3 }, string.Empty);

        Assert.Equal("你好，世界。", result);
    }

    [Fact]
    public async Task WritingModel_ParsesSnakeCaseJsonFields()
    {
        const string guidanceJson =
            "{\"framework\":[\"开场\"],\"next_sentence\":\"下一句提示\","
            + "\"directions\":[\"展开功能\"],\"missing_points\":[\"补充案例\"]}";
        const string optimizeJson =
            "{\"optimized_text\":\"优化后的全文。\",\"changes\":[]}";

        var responses = new Queue<string>([guidanceJson, optimizeJson]);
        using var httpClient = new HttpClient(new StubHttpMessageHandler(_ =>
        {
            var responseJson = responses.Dequeue();

            var completion = $$"""
                {
                  "choices": [
                    {
                      "message": {
                        "content": {{System.Text.Json.JsonSerializer.Serialize(responseJson)}}
                      }
                    }
                  ]
                }
                """;
            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(completion, Encoding.UTF8, "application/json")
            };
        }));
        var provider = new ZhipuWritingModelProvider(httpClient, new StubApiKeyStore());

        var guidance = await provider.AnalyzeAsync("当前全文", null);
        var optimized = await provider.OptimizeSegmentsAsync(["片段1：原文"]);

        Assert.Equal("下一句提示", guidance.NextSentence);
        Assert.Equal(["补充案例"], guidance.MissingPoints);
        Assert.Equal("优化后的全文。", optimized);
    }

    [Fact]
    public async Task ApiKeyStore_RoundTripsDpapiProtectedSecret()
    {
        var directory = Path.Combine(Path.GetTempPath(), "JT.Copilot.KeyTests", Guid.NewGuid().ToString("N"));
        var path = Path.Combine(directory, "key.bin");

        try
        {
            var store = new ZhipuApiKeyStore(
                path,
                NullLogger<ZhipuApiKeyStore>.Instance);

            await store.SaveApiKeyAsync("test-api-key");
            var result = await store.GetApiKeyAsync();
            var fileText = Encoding.UTF8.GetString(await File.ReadAllBytesAsync(path));

            Assert.Equal("test-api-key", result);
            Assert.DoesNotContain("test-api-key", fileText, StringComparison.Ordinal);
        }
        finally
        {
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, recursive: true);
            }
        }
    }

    private sealed class StubApiKeyStore : IZhipuApiKeyStore
    {
        public Task<string?> GetApiKeyAsync(CancellationToken cancellationToken = default)
        {
            return Task.FromResult<string?>("test-key");
        }

        public Task SaveApiKeyAsync(string apiKey, CancellationToken cancellationToken = default)
        {
            return Task.CompletedTask;
        }
    }

    private sealed class StubHttpMessageHandler(
        Func<HttpRequestMessage, HttpResponseMessage> handler) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(handler(request));
        }
    }
}
