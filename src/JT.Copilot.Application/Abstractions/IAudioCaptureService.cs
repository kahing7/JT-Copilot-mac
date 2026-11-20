using JT.Copilot.Application.Models;

namespace JT.Copilot.Application.Abstractions;

public interface IAudioCaptureService : IDisposable
{
    event EventHandler<AudioLevelChangedEventArgs>? LevelChanged;

    bool IsCapturing { get; }

    IReadOnlyList<AudioDeviceDescriptor> GetInputDevices();

    Task StartAsync(string? deviceId, CancellationToken cancellationToken = default);

    Task<AudioCaptureResult> StopAsync(CancellationToken cancellationToken = default);

    void Cancel();
}
