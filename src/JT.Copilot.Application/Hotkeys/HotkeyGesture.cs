namespace JT.Copilot.Application.Hotkeys;

public sealed class HotkeyGesture
{
    private const int MaxVirtualKeys = 4;
    private static readonly IReadOnlyDictionary<string, int> NamedVirtualKeys =
        new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
        {
            ["Space"] = 0x20,
            ["Enter"] = 0x0D,
            ["Tab"] = 0x09,
            ["Backspace"] = 0x08,
            ["Esc"] = 0x1B,
            ["Escape"] = 0x1B,
            ["Insert"] = 0x2D,
            ["Delete"] = 0x2E,
            ["Home"] = 0x24,
            ["End"] = 0x23,
            ["PageUp"] = 0x21,
            ["PageDown"] = 0x22,
            ["Left"] = 0x25,
            ["Up"] = 0x26,
            ["Right"] = 0x27,
            ["Down"] = 0x28
        };

    private static readonly IReadOnlyDictionary<int, string> NamedVirtualKeyLabels =
        NamedVirtualKeys
            .GroupBy(pair => pair.Value)
            .ToDictionary(group => group.Key, group => group.First().Key);

    private readonly int[] _virtualKeys;

    private HotkeyGesture(HotkeyModifiers modifiers, IEnumerable<int> virtualKeys)
    {
        Modifiers = modifiers;
        _virtualKeys = virtualKeys.ToArray();
    }

    public static HotkeyGesture Default { get; } =
        new(HotkeyModifiers.Control | HotkeyModifiers.Shift, [0x4A, 0x54]);

    public HotkeyModifiers Modifiers { get; }

    public IReadOnlyList<int> VirtualKeys => _virtualKeys;

    public string DisplayText => ToSettingString().Replace("+", " + ", StringComparison.Ordinal);

    public static HotkeyGesture ParseOrDefault(string? value)
    {
        return TryParse(value, out var gesture) ? gesture : Default;
    }

    public static bool TryParse(string? value, out HotkeyGesture gesture)
    {
        gesture = Default;
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var modifiers = HotkeyModifiers.None;
        var virtualKeys = new List<int>();

        foreach (var rawToken in value.Split('+', StringSplitOptions.RemoveEmptyEntries))
        {
            var token = rawToken.Trim();
            if (TryParseModifier(token, out var modifier))
            {
                modifiers |= modifier;
                continue;
            }

            if (!TryParseVirtualKey(token, out var virtualKey))
            {
                return false;
            }

            virtualKeys.Add(virtualKey);
        }

        return TryCreate(modifiers, virtualKeys, out gesture);
    }

    public static bool TryCreate(
        HotkeyModifiers modifiers,
        IEnumerable<int> virtualKeys,
        out HotkeyGesture gesture)
    {
        gesture = Default;
        var distinctKeys = virtualKeys
            .Where(key => key is > 0 and <= 0xFF && !IsModifierVirtualKey(key))
            .Distinct()
            .Take(MaxVirtualKeys + 1)
            .ToArray();

        var hasPrimaryModifier = (modifiers &
            (HotkeyModifiers.Control | HotkeyModifiers.Alt | HotkeyModifiers.Windows)) != 0;

        if (!hasPrimaryModifier
            || distinctKeys.Length is 0 or > MaxVirtualKeys
            || distinctKeys.Contains(0x1B))
        {
            return false;
        }

        gesture = new HotkeyGesture(modifiers, distinctKeys);
        return true;
    }

    public string ToSettingString()
    {
        var parts = new List<string>(4);

        if (Modifiers.HasFlag(HotkeyModifiers.Control))
        {
            parts.Add("Ctrl");
        }

        if (Modifiers.HasFlag(HotkeyModifiers.Shift))
        {
            parts.Add("Shift");
        }

        if (Modifiers.HasFlag(HotkeyModifiers.Alt))
        {
            parts.Add("Alt");
        }

        if (Modifiers.HasFlag(HotkeyModifiers.Windows))
        {
            parts.Add("Win");
        }

        parts.AddRange(_virtualKeys.Select(GetVirtualKeyLabel));
        return string.Join('+', parts);
    }

    public static bool IsModifierVirtualKey(int virtualKey)
    {
        return virtualKey is 0x10 or 0x11 or 0x12 or 0x5B or 0x5C
            or 0xA0 or 0xA1 or 0xA2 or 0xA3 or 0xA4 or 0xA5;
    }

    private static bool TryParseModifier(string token, out HotkeyModifiers modifier)
    {
        switch (token.ToUpperInvariant())
        {
            case "CTRL":
            case "CONTROL":
                modifier = HotkeyModifiers.Control;
                return true;
            case "SHIFT":
                modifier = HotkeyModifiers.Shift;
                return true;
            case "ALT":
                modifier = HotkeyModifiers.Alt;
                return true;
            case "WIN":
            case "WINDOWS":
                modifier = HotkeyModifiers.Windows;
                return true;
            default:
                modifier = HotkeyModifiers.None;
                return false;
        }
    }

    private static bool TryParseVirtualKey(string token, out int virtualKey)
    {
        virtualKey = 0;

        if (token.Length == 1)
        {
            var character = char.ToUpperInvariant(token[0]);
            if (character is >= 'A' and <= 'Z' or >= '0' and <= '9')
            {
                virtualKey = character;
                return true;
            }
        }

        if (token.Length is 2 or 3
            && token[0] is 'F' or 'f'
            && int.TryParse(token[1..], out var functionNumber)
            && functionNumber is >= 1 and <= 24)
        {
            virtualKey = 0x70 + functionNumber - 1;
            return true;
        }

        if (NamedVirtualKeys.TryGetValue(token, out virtualKey))
        {
            return true;
        }

        if (token.StartsWith("VK_", StringComparison.OrdinalIgnoreCase)
            && int.TryParse(token[3..], System.Globalization.NumberStyles.HexNumber, null, out virtualKey))
        {
            return virtualKey is > 0 and <= 0xFF;
        }

        return false;
    }

    private static string GetVirtualKeyLabel(int virtualKey)
    {
        if (virtualKey is >= 'A' and <= 'Z' or >= '0' and <= '9')
        {
            return ((char)virtualKey).ToString();
        }

        if (virtualKey is >= 0x70 and <= 0x87)
        {
            return $"F{virtualKey - 0x70 + 1}";
        }

        return NamedVirtualKeyLabels.TryGetValue(virtualKey, out var label)
            ? label
            : $"VK_{virtualKey:X2}";
    }
}
