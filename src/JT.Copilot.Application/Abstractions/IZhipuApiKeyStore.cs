namespace JT.Copilot.Application.Abstractions;

public interface IZhipuApiKeyStore
{
    Task<string?> GetApiKeyAsync(CancellationToken cancellationToken = default);

    Task SaveApiKeyAsync(string apiKey, CancellationToken cancellationToken = default);
}
