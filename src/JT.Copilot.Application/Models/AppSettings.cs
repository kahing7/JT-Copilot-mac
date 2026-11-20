namespace JT.Copilot.Application.Models;

public sealed record AppSettings
{
    public const string DefaultHotkey = "Ctrl+Alt+Space";

    public int SchemaVersion { get; init; } = 1;

    public string PreferredMicrophoneDeviceId { get; init; } = string.Empty;

    public string Hotkey { get; init; } = DefaultHotkey;

    public bool IsTopmost { get; init; } = true;

    public double? WindowLeft { get; init; }

    public double? WindowTop { get; init; }

    public bool IsExpanded { get; init; } = true;

    public AppSettings Normalize()
    {
        return this with
        {
            SchemaVersion = 1,
            PreferredMicrophoneDeviceId = PreferredMicrophoneDeviceId?.Trim() ?? string.Empty,
            Hotkey = string.IsNullOrWhiteSpace(Hotkey) ? DefaultHotkey : Hotkey.Trim()
        };
    }
}
