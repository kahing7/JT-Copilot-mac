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
        Assert.Equal(AppSettings.CurrentSchemaVersion, normalized.SchemaVersion);
    }

    [Fact]
    public void Normalize_MigratesLegacyDefaultHotkey()
    {
        var settings = new AppSettings
        {
            SchemaVersion = 1,
            Hotkey = "Ctrl+Alt+Space"
        };

        var normalized = settings.Normalize();

        Assert.Equal("Ctrl+Shift+J+T", normalized.Hotkey);
        Assert.Equal(AppSettings.CurrentSchemaVersion, normalized.SchemaVersion);
    }

    [Fact]
    public void Normalize_ReplacesInvalidHotkeyWithDefault()
    {
        var settings = new AppSettings
        {
            Hotkey = "Shift+T"
        };

        var normalized = settings.Normalize();

        Assert.Equal(AppSettings.DefaultHotkey, normalized.Hotkey);
    }

    [Fact]
    public void Normalize_ClampsGlassOpacityRanges()
    {
        var settings = new AppSettings
        {
            OrbOpacityPercent = 5,
            GuidanceOpacityPercent = 130
        };

        var normalized = settings.Normalize();

        Assert.Equal(35, normalized.OrbOpacityPercent);
        Assert.Equal(100, normalized.GuidanceOpacityPercent);
    }

    [Fact]
    public void Normalize_RejectsUnknownGuidanceTemplate()
    {
        var settings = new AppSettings
        {
            GuidanceTemplate = (DocumentTemplate)999
        };

        var normalized = settings.Normalize();

        Assert.Equal(DocumentTemplate.Auto, normalized.GuidanceTemplate);
    }
}
