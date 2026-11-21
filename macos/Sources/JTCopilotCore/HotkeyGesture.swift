import Foundation

public struct HotkeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let control = HotkeyModifiers(rawValue: 1 << 0)
    public static let shift = HotkeyModifiers(rawValue: 1 << 1)
    public static let option = HotkeyModifiers(rawValue: 1 << 2)
    public static let command = HotkeyModifiers(rawValue: 1 << 3)

    /// Windows 命名兼容：Alt 即 Option，Win 即 Command。
    public static let alt = HotkeyModifiers.option
    public static let windows = HotkeyModifiers.command
}

public struct HotkeyKey: Hashable, Sendable {
    public let label: String
    public let macKeyCode: UInt16
    public let windowsVirtualKey: Int

    public init(label: String, macKeyCode: UInt16, windowsVirtualKey: Int) {
        self.label = label
        self.macKeyCode = macKeyCode
        self.windowsVirtualKey = windowsVirtualKey
    }

    public static func == (lhs: HotkeyKey, rhs: HotkeyKey) -> Bool {
        lhs.macKeyCode == rhs.macKeyCode
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(macKeyCode)
    }
}

public enum HotkeyKeyCatalog {
    private static let letters: [(String, UInt16, Int)] = [
        ("A", 0x00, 0x41), ("S", 0x01, 0x53), ("D", 0x02, 0x44), ("F", 0x03, 0x46),
        ("H", 0x04, 0x48), ("G", 0x05, 0x47), ("Z", 0x06, 0x5A), ("X", 0x07, 0x58),
        ("C", 0x08, 0x43), ("V", 0x09, 0x56), ("B", 0x0B, 0x42), ("Q", 0x0C, 0x51),
        ("W", 0x0D, 0x57), ("E", 0x0E, 0x45), ("R", 0x0F, 0x52), ("Y", 0x10, 0x59),
        ("T", 0x11, 0x54), ("O", 0x1F, 0x4F), ("U", 0x20, 0x55), ("I", 0x22, 0x49),
        ("P", 0x23, 0x50), ("L", 0x25, 0x4C), ("J", 0x26, 0x4A), ("K", 0x28, 0x4B),
        ("N", 0x2D, 0x4E), ("M", 0x2E, 0x4D)
    ]

    private static let digits: [(String, UInt16, Int)] = [
        ("1", 0x12, 0x31), ("2", 0x13, 0x32), ("3", 0x14, 0x33), ("4", 0x15, 0x34),
        ("6", 0x16, 0x36), ("5", 0x17, 0x35), ("9", 0x19, 0x39), ("7", 0x1A, 0x37),
        ("8", 0x1C, 0x38), ("0", 0x1D, 0x30)
    ]

    private static let named: [(String, UInt16, Int)] = [
        ("Space", 0x31, 0x20),
        ("Enter", 0x24, 0x0D),
        ("Return", 0x24, 0x0D),
        ("Tab", 0x30, 0x09),
        ("Backspace", 0x33, 0x08),
        ("Delete", 0x75, 0x2E),
        ("Esc", 0x35, 0x1B),
        ("Escape", 0x35, 0x1B),
        ("Home", 0x73, 0x24),
        ("End", 0x77, 0x23),
        ("PageUp", 0x74, 0x21),
        ("PageDown", 0x79, 0x22),
        ("Left", 0x7B, 0x25),
        ("Up", 0x7E, 0x26),
        ("Right", 0x7C, 0x27),
        ("Down", 0x7D, 0x28),
        ("Minus", 0x1B, 0xBD),
        ("Equal", 0x18, 0xBB),
        ("LeftBracket", 0x21, 0xDB),
        ("RightBracket", 0x1E, 0xDD),
        ("Backslash", 0x2A, 0xDC),
        ("Semicolon", 0x29, 0xBA),
        ("Quote", 0x27, 0xDE),
        ("Comma", 0x2B, 0xBC),
        ("Period", 0x2F, 0xBE),
        ("Slash", 0x2C, 0xBF),
        ("Grave", 0x32, 0xC0)
    ]

    private static let functionKeyCodes: [Int] = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
        103, 111, 105, 107, 113, 106, 64, 79, 80, 90
    ]

    private static let functions: [(String, UInt16, Int)] = functionKeyCodes.enumerated().map { index, code in
        ("F\(index + 1)", UInt16(code), 0x70 + index)
    }

    private static let allEntries: [(String, UInt16, Int)] = letters + digits + functions + named

    public static let allKeys: [HotkeyKey] = {
        var seen = Set<UInt16>()
        var result: [HotkeyKey] = []
        for (label, macCode, windowsCode) in allEntries where !seen.contains(macCode) {
            seen.insert(macCode)
            result.append(HotkeyKey(label: label, macKeyCode: macCode, windowsVirtualKey: windowsCode))
        }
        return result
    }()

    private static let byLabel: [String: HotkeyKey] = {
        var map: [String: HotkeyKey] = [:]
        for key in allKeys {
            map[key.label.lowercased()] = key
        }
        return map
    }()

    private static let byMacCode: [UInt16: HotkeyKey] = {
        Dictionary(uniqueKeysWithValues: allKeys.map { ($0.macKeyCode, $0) })
    }()

    private static let byWindowsCode: [Int: HotkeyKey] = {
        var map: [Int: HotkeyKey] = [:]
        for key in allKeys where map[key.windowsVirtualKey] == nil {
            map[key.windowsVirtualKey] = key
        }
        return map
    }()

    public static func key(forLabel label: String) -> HotkeyKey? {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.count == 1, let character = trimmed.first,
           character.isASCII, character.isLetter || character.isNumber {
            return byLabel[String(character).lowercased()]
        }

        return byLabel[trimmed.lowercased()]
    }

    public static func key(forMacKeyCode code: UInt16) -> HotkeyKey? {
        byMacCode[code]
    }

    public static func key(forWindowsVirtualKey code: Int) -> HotkeyKey? {
        byWindowsCode[code]
    }

    public static func isModifierKeyCode(_ code: UInt16) -> Bool {
        // Command / Shift / CapsLock / Option / Control / Function / 左右变体。
        switch code {
        case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63:
            return true
        default:
            return false
        }
    }
}

public struct HotkeyGesture: Equatable, Sendable {
    public static let maximumKeyCount = 4

    public let modifiers: HotkeyModifiers
    public let keys: [HotkeyKey]

    private init(modifiers: HotkeyModifiers, keys: [HotkeyKey]) {
        self.modifiers = modifiers
        self.keys = keys
    }

    /// Windows 版默认值：Ctrl + Shift + J + T 同时按下。
    public static let defaultGesture: HotkeyGesture = {
        let j = HotkeyKeyCatalog.key(forLabel: "J")!
        let t = HotkeyKeyCatalog.key(forLabel: "T")!
        return HotkeyGesture(modifiers: [.control, .shift], keys: [j, t])
    }()

    public var settingString: String {
        var parts: [String] = []

        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.option) { parts.append("Alt") }
        if modifiers.contains(.command) { parts.append("Cmd") }
        parts.append(contentsOf: keys.map(\.label))

        return parts.joined(separator: "+")
    }

    public var displayText: String {
        settingString.replacingOccurrences(of: "+", with: " + ")
    }

    /// macOS 习惯的符号显示，例如 ⌃⇧J T。
    public var macDisplayText: String {
        var parts = ""
        if modifiers.contains(.control) { parts += "⌃" }
        if modifiers.contains(.option) { parts += "⌥" }
        if modifiers.contains(.shift) { parts += "⇧" }
        if modifiers.contains(.command) { parts += "⌘" }
        return parts + keys.map(\.label).joined(separator: " ")
    }

    public var macKeyCodes: [UInt16] {
        keys.map(\.macKeyCode)
    }

    public static func parseOrDefault(_ value: String?) -> HotkeyGesture {
        parse(value) ?? defaultGesture
    }

    public static func parse(_ value: String?) -> HotkeyGesture? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        var modifiers: HotkeyModifiers = []
        var keys: [HotkeyKey] = []

        for rawToken in value.split(separator: "+", omittingEmptySubsequences: true) {
            let token = rawToken.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty else { continue }

            switch token.lowercased() {
            case "ctrl", "control":
                modifiers.insert(.control)
                continue
            case "shift":
                modifiers.insert(.shift)
                continue
            case "alt", "option", "opt":
                modifiers.insert(.option)
                continue
            case "win", "windows", "cmd", "command", "meta":
                modifiers.insert(.command)
                continue
            default:
                break
            }

            if token.lowercased().hasPrefix("vk_"),
               let value = Int(token.dropFirst(3), radix: 16),
               let key = HotkeyKeyCatalog.key(forWindowsVirtualKey: value) {
                keys.append(key)
                continue
            }

            guard let key = HotkeyKeyCatalog.key(forLabel: token) else {
                return nil
            }

            keys.append(key)
        }

        return create(modifiers: modifiers, keys: keys)
    }

    public static func create(modifiers: HotkeyModifiers, keys: [HotkeyKey]) -> HotkeyGesture? {
        var seen = Set<UInt16>()
        var distinct: [HotkeyKey] = []

        for key in keys where !seen.contains(key.macKeyCode) {
            seen.insert(key.macKeyCode)
            distinct.append(key)
        }

        let hasPrimaryModifier = !modifiers.intersection([.control, .option, .command]).isEmpty
        let containsEscape = distinct.contains { $0.macKeyCode == 0x35 }

        guard hasPrimaryModifier,
              (1...maximumKeyCount).contains(distinct.count),
              !containsEscape else {
            return nil
        }

        return HotkeyGesture(modifiers: modifiers, keys: distinct)
    }

    public static func create(modifiers: HotkeyModifiers, keyLabels: [String]) -> HotkeyGesture? {
        let keys = keyLabels.compactMap(HotkeyKeyCatalog.key(forLabel:))
        guard keys.count == keyLabels.count else {
            return nil
        }

        return create(modifiers: modifiers, keys: keys)
    }

    public static func create(modifiers: HotkeyModifiers, macKeyCodes: [UInt16]) -> HotkeyGesture? {
        let keys = macKeyCodes.compactMap(HotkeyKeyCatalog.key(forMacKeyCode:))
        guard keys.count == macKeyCodes.count else {
            return nil
        }

        return create(modifiers: modifiers, keys: keys)
    }
}
