using JT.Copilot.Application.Models;

namespace JT.Copilot.Application.Abstractions;

public interface IAudioCaptureService : IDisposable
{
    event EventHandler<AudioLevelChangedEventArgs>? LevelChanged;

    event EventHandler<PcmAudioDataEventArgs>? PcmDataAvailable;

    bool IsCapturing { get; }

    IReadOnlyList<AudioDeviceDescriptor> GetInputDevices();

    Task StartAsync(string? deviceId, CancellationToken cancellationToken = default);

    Task<AudioCaptureResult> StopAsync(CancellationToken cancellationToken = default);

    void Cancel();
}
