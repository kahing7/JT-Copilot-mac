using JT.Copilot.Application.Models;

namespace JT.Copilot.UnitTests;

public sealed class AppSettingsTests
{
    [Fact]
    public void Normalize_RestoresDefaultHotkeyAndTrimsMicrophoneId()
    {
        var settings = new AppSettings
        {
            Hotkey = " ",
            PreferredMicrophoneDeviceId = "  2  "
        };

        var normalized = settings.Normalize();

        Assert.Equal(AppSettings.DefaultHotkey, normalized.Hotkey);
        Assert.Equal("2", normalized.PreferredMicrophoneDeviceId);
        Assert.Equal(1, normalized.SchemaVersion);
    }
}
