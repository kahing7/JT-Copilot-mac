using System.IO;
using System.IO.Compression;
using System.Net.Http;
using JT.Copilot.Infrastructure.Storage;
using Microsoft.Extensions.Logging;

namespace JT.Copilot.Infrastructure.Audio;

public sealed class VoskModelProvisioner
{
    private const string ModelDownloadUrl =
        "https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip";
    private readonly HttpClient _httpClient;
    private readonly ILogger<VoskModelProvisioner> _logger;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public VoskModelProvisioner(
        HttpClient httpClient,
        ILogger<VoskModelProvisioner> logger)
    {
        _httpClient = httpClient;
        _logger = logger;
    }

    public async Task<string> EnsureModelAsync(CancellationToken cancellationToken = default)
    {
        if (IsValidModel(AppPaths.VoskModelDirectory))
        {
            return AppPaths.VoskModelDirectory;
        }

        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);

        try
        {
            if (IsValidModel(AppPaths.VoskModelDirectory))
            {
                return AppPaths.VoskModelDirectory;
            }

            Directory.CreateDirectory(AppPaths.ModelsDirectory);
            var archivePath = Path.Combine(AppPaths.ModelsDirectory, "vosk-model-small-cn-0.22.zip");
            var extractionPath = Path.Combine(AppPaths.ModelsDirectory, "vosk-extract");

            _logger.LogInformation("Downloading the local Vosk Chinese model.");
            await DownloadAsync(archivePath, cancellationToken).ConfigureAwait(false);

            if (Directory.Exists(extractionPath))
            {
                Directory.Delete(extractionPath, recursive: true);
            }

            ZipFile.ExtractToDirectory(archivePath, extractionPath);
            var extractedModel = Directory
                .EnumerateDirectories(extractionPath)
                .FirstOrDefault(IsValidModel);

            if (extractedModel is null)
            {
                throw new InvalidOperationException("下载的 Vosk 模型结构无效。");
            }

            if (Directory.Exists(AppPaths.VoskModelDirectory))
            {
                Directory.Delete(AppPaths.VoskModelDirectory, recursive: true);
            }

            Directory.Move(extractedModel, AppPaths.VoskModelDirectory);
            File.Delete(archivePath);
            Directory.Delete(extractionPath, recursive: true);
            return AppPaths.VoskModelDirectory;
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task DownloadAsync(string destinationPath, CancellationToken cancellationToken)
    {
        using var response = await _httpClient
            .GetAsync(ModelDownloadUrl, HttpCompletionOption.ResponseHeadersRead, cancellationToken)
            .ConfigureAwait(false);
        response.EnsureSuccessStatusCode();

        await using var source = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
        await using var destination = File.Create(destinationPath);
        await source.CopyToAsync(destination, cancellationToken).ConfigureAwait(false);
    }

    private static bool IsValidModel(string path)
    {
        return Directory.Exists(Path.Combine(path, "am"))
            && Directory.Exists(Path.Combine(path, "conf"));
    }
}
