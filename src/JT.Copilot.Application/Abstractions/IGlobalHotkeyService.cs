namespace JT.Copilot.Application.Abstractions;

public interface IGlobalHotkeyService : IDisposable
{
    event EventHandler? Pressed;

    event EventHandler? Released;

    event EventHandler? CancelRequested;

    bool IsRunning { get; }

    void Start();

    void Stop();
}
