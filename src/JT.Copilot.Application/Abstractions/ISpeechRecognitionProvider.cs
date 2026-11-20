namespace JT.Copilot.Application.Abstractions;

public interface ISpeechRecognitionProvider
{
    Task<string> TranscribeAsync(
        ReadOnlyMemory<byte> wavAudio,
        string transcriptContext,
        CancellationToken cancellationToken = default);
}
