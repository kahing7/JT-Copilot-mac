using System.IO;
using System.Security.Cryptography;
using System.Text;
using JT.Copilot.Application.Abstractions;
using Microsoft.Extensions.Logging;

namespace JT.Copilot.Infrastructure.Security;

public sealed class ZhipuApiKeyStore : IZhipuApiKeyStore
{
    private const string EnvironmentVariableName = "ZHIPU_API_KEY";
    private readonly string _filePath;
    private readonly ILogger<ZhipuApiKeyStore> _logger;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public ZhipuApiKeyStore(
        string filePath,
        ILogger<ZhipuApiKeyStore> logger)
    {
        _filePath = filePath;
        _logger = logger;
    }

    public async Task<string?> GetApiKeyAsync(CancellationToken cancellationToken = default)
    {
        var environmentValue = Environment.GetEnvironmentVariable(EnvironmentVariableName);
        if (!string.IsNullOrWhiteSpace(environmentValue))
        {
            return environmentValue.Trim();
        }

        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);

        try
        {
            if (!File.Exists(_filePath))
            {
                return null;
            }

            var protectedBytes = await File.ReadAllBytesAsync(_filePath, cancellationToken).ConfigureAwait(false);
            var plainBytes = ProtectedData.Unprotect(
                protectedBytes,
                optionalEntropy: null,
                DataProtectionScope.CurrentUser);

            return Encoding.UTF8.GetString(plainBytes).Trim();
        }
        catch (Exception exception) when (
            exception is IOException
            or UnauthorizedAccessException
            or CryptographicException)
        {
            _logger.LogError(exception, "Unable to read the encrypted Zhipu API key.");
            return null;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task SaveApiKeyAsync(string apiKey, CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(apiKey);
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);

        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);
            var plainBytes = Encoding.UTF8.GetBytes(apiKey.Trim());
            var protectedBytes = ProtectedData.Protect(
                plainBytes,
                optionalEntropy: null,
                DataProtectionScope.CurrentUser);

            var temporaryPath = $"{_filePath}.{Guid.NewGuid():N}.tmp";
            await File.WriteAllBytesAsync(temporaryPath, protectedBytes, cancellationToken).ConfigureAwait(false);
            File.Move(temporaryPath, _filePath, overwrite: true);
        }
        finally
        {
            _gate.Release();
        }
    }
}
