using JT.Copilot.Application.Hotkeys;

namespace JT.Copilot.Application.Abstractions;

public interface IGlobalHotkeyService : IDisposable
{
    event EventHandler? Pressed;

    event EventHandler? Released;

    event EventHandler? CancelRequested;

    bool IsRunning { get; }

    bool CaptureEscape { get; set; }

    HotkeyGesture Gesture { get; }

    void Start(HotkeyGesture gesture);

    void Reconfigure(HotkeyGesture gesture);

    void Stop();
}
