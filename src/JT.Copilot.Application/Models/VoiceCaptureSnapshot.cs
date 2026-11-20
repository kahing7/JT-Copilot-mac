using JT.Copilot.Domain.Enums;

namespace JT.Copilot.Application.Models;

public sealed record VoiceCaptureSnapshot(
    VoiceCaptureState State,
    TimeSpan Elapsed,
    string? RecordingPath = null,
    string? ErrorMessage = null)
{
    public static VoiceCaptureSnapshot Idle { get; } =
        new(VoiceCaptureState.Idle, TimeSpan.Zero);
}

public sealed class VoiceCaptureStateChangedEventArgs(VoiceCaptureSnapshot snapshot) : EventArgs
{
    public VoiceCaptureSnapshot Snapshot { get; } = snapshot;
}

public sealed class AudioLevelChangedEventArgs(double level) : EventArgs
{
    public double Level { get; } = level;
}
