using JT.Copilot.Application.Hotkeys;

namespace JT.Copilot.UnitTests;

public sealed class HotkeyGestureTests
{
    [Fact]
    public void Default_UsesRequestedFourKeyChord()
    {
        Assert.Equal("Ctrl+Shift+J+T", HotkeyGesture.Default.ToSettingString());
        Assert.Equal("Ctrl + Shift + J + T", HotkeyGesture.Default.DisplayText);
    }

    [Fact]
    public void Parse_NormalizesModifierAndKeyOrder()
    {
        var parsed = HotkeyGesture.ParseOrDefault("Shift+Control+T+J");

        Assert.Equal("Ctrl+Shift+T+J", parsed.ToSettingString());
    }

    [Theory]
    [InlineData("T")]
    [InlineData("Shift+T")]
    [InlineData("Ctrl+Escape")]
    [InlineData("Ctrl+")]
    [InlineData("Ctrl+NotAKey")]
    public void Parse_RejectsUnsafeOrInvalidGestures(string value)
    {
        var parsed = HotkeyGesture.ParseOrDefault(value);

        Assert.Equal(HotkeyGesture.Default, parsed);
    }

    [Fact]
    public void TryCreate_AllowsMultipleNonModifierKeys()
    {
        var created = HotkeyGesture.TryCreate(
            HotkeyModifiers.Control | HotkeyModifiers.Alt,
            [0x4A, 0x54],
            out var gesture);

        Assert.True(created);
        Assert.Equal("Ctrl+Alt+J+T", gesture.ToSettingString());
    }
}
