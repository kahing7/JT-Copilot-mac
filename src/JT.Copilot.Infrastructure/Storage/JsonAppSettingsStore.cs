using System.Text.Json;
using JT.Copilot.Application.Abstractions;
using JT.Copilot.Application.Models;
using Microsoft.Extensions.Logging;

namespace JT.Copilot.Infrastructure.Storage;

public sealed class JsonAppSettingsStore : IAppSettingsStore
{
    private static readonly JsonSerializerOptions SerializerOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true
    };

    private readonly string _settingsFilePath;
    private readonly ILogger<JsonAppSettingsStore>? _logger;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public JsonAppSettingsStore(
        string settingsFilePath,
        ILogger<JsonAppSettingsStore>? logger = null)
    {
        _settingsFilePath = settingsFilePath;
        _logger = logger;
    }

    public async Task<AppSettings> LoadAsync(CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);

        try
        {
            if (!File.Exists(_settingsFilePath))
            {
                return new AppSettings();
            }

            await using var stream = File.OpenRead(_settingsFilePath);
            var settings = await JsonSerializer
                .DeserializeAsync<AppSettings>(stream, SerializerOptions, cancellationToken)
                .ConfigureAwait(false);

            return (settings ?? new AppSettings()).Normalize();
        }
        catch (JsonException exception)
        {
            _logger?.LogWarning(exception, "Settings file is invalid. Defaults will be used.");
            return new AppSettings();
        }
        catch (IOException exception)
        {
            _logger?.LogWarning(exception, "Settings file could not be read. Defaults will be used.");
            return new AppSettings();
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task SaveAsync(AppSettings settings, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(settings);
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);

        try
        {
            var directory = Path.GetDirectoryName(_settingsFilePath);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var temporaryPath = $"{_settingsFilePath}.{Guid.NewGuid():N}.tmp";
            await using (var stream = File.Create(temporaryPath))
            {
                await JsonSerializer
                    .SerializeAsync(stream, settings.Normalize(), SerializerOptions, cancellationToken)
                    .ConfigureAwait(false);
            }

            File.Move(temporaryPath, _settingsFilePath, overwrite: true);
        }
        finally
        {
            _gate.Release();
        }
    }
}
