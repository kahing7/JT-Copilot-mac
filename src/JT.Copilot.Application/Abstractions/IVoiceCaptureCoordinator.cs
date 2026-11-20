using JT.Copilot.Application.Hotkeys;
using JT.Copilot.Application.Models;

namespace JT.Copilot.Application.Abstractions;

public interface IVoiceCaptureCoordinator : IDisposable
{
    event EventHandler<VoiceCaptureStateChangedEventArgs>? StateChanged;

    event EventHandler<AudioLevelChangedEventArgs>? LevelChanged;

    event EventHandler<WritingSessionUpdateEventArgs>? WritingSessionChanged;

    VoiceCaptureSnapshot Current { get; }

    WritingSessionUpdate CurrentWritingSession { get; }

    Task InitializeAsync(CancellationToken cancellationToken = default);

    Task StartAsync(CancellationToken cancellationToken = default);

    Task StopAsync(CancellationToken cancellationToken = default);

    Task FinishAsync(CancellationToken cancellationToken = default);

    Task CancelAsync(CancellationToken cancellationToken = default);

    void UpdateHotkey(HotkeyGesture gesture);
}
