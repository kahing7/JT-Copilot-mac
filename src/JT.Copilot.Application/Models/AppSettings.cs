using JT.Copilot.Application.Hotkeys;

namespace JT.Copilot.Application.Models;

public sealed record AppSettings
{
    public const string DefaultHotkey = "Ctrl+Shift+J+T";
    public const int CurrentSchemaVersion = 2;

    public int SchemaVersion { get; init; } = CurrentSchemaVersion;

    public string PreferredMicrophoneDeviceId { get; init; } = string.Empty;

    public string Hotkey { get; init; } = DefaultHotkey;

    public bool IsTopmost { get; init; } = true;

    public double OrbOpacityPercent { get; init; } = 78;

    public double GuidanceOpacityPercent { get; init; } = 68;

    public double? WindowLeft { get; init; }

    public double? WindowTop { get; init; }

    public bool IsExpanded { get; init; } = true;

    public AppSettings Normalize()
    {
        // Version 1 always used Ctrl+Alt+Space because the setting was read-only.
        var hotkey = SchemaVersion < CurrentSchemaVersion
            && string.Equals(Hotkey, "Ctrl+Alt+Space", StringComparison.OrdinalIgnoreCase)
                ? DefaultHotkey
                : Hotkey;

        if (!HotkeyGesture.TryParse(hotkey, out var gesture))
        {
            gesture = HotkeyGesture.Default;
        }

        return this with
        {
            SchemaVersion = CurrentSchemaVersion,
            PreferredMicrophoneDeviceId = PreferredMicrophoneDeviceId?.Trim() ?? string.Empty,
            Hotkey = gesture.ToSettingString(),
            OrbOpacityPercent = Math.Clamp(OrbOpacityPercent, 35, 100),
            GuidanceOpacityPercent = Math.Clamp(GuidanceOpacityPercent, 40, 100)
        };
    }
}
