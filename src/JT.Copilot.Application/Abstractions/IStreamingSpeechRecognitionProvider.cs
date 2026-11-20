using JT.Copilot.Application.Models;

namespace JT.Copilot.Application.Abstractions;

public interface IStreamingSpeechRecognitionProvider : IDisposable
{
    event EventHandler<LiveTranscriptEventArgs>? TranscriptChanged;

    bool IsAvailable { get; }

    Task<bool> InitializeAsync(CancellationToken cancellationToken = default);

    void StartSession();

    void PushAudio(ReadOnlyMemory<byte> pcmAudio);

    string EndSession();
}
