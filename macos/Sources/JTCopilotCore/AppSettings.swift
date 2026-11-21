import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public static let defaultHotkey = "Ctrl+Shift+J+T"
    public static let currentSchemaVersion = 3

    public var schemaVersion: Int
    public var preferredMicrophoneDeviceId: String
    public var hotkey: String
    public var customVocabulary: String
    public var isTopmost: Bool
    public var orbOpacityPercent: Double
    public var guidanceOpacityPercent: Double
    public var guidanceTemplate: DocumentTemplate
    public var windowLeft: Double?
    public var windowTop: Double?
    public var isExpanded: Bool

    public init(
        schemaVersion: Int = AppSettings.currentSchemaVersion,
        preferredMicrophoneDeviceId: String = "",
        hotkey: String = AppSettings.defaultHotkey,
        customVocabulary: String = AppSettings.defaultCustomVocabulary,
        isTopmost: Bool = true,
        orbOpacityPercent: Double = 78,
        guidanceOpacityPercent: Double = 68,
        guidanceTemplate: DocumentTemplate = .auto,
        windowLeft: Double? = nil,
        windowTop: Double? = nil,
        isExpanded: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.preferredMicrophoneDeviceId = preferredMicrophoneDeviceId
        self.hotkey = hotkey
        self.customVocabulary = customVocabulary
        self.isTopmost = isTopmost
        self.orbOpacityPercent = orbOpacityPercent
        self.guidanceOpacityPercent = guidanceOpacityPercent
        self.guidanceTemplate = guidanceTemplate
        self.windowLeft = windowLeft
        self.windowTop = windowTop
        self.isExpanded = isExpanded
    }

    public static let defaultCustomVocabulary =
        "CRM系统=新奥尔良系统,新奥良系统\n"
        + "积分兑礼=积分队里区,积分队里,积分兑换\n"
        + "OK=欧克,欧凯"

    public var hotkeyGesture: HotkeyGesture {
        HotkeyGesture.parseOrDefault(hotkey)
    }

    public func normalized() -> AppSettings {
        // 版本 1 的默认快捷键是只读的 Ctrl+Alt+Space，升级时迁移到当前默认值。
        let migratedHotkey: String
        if schemaVersion < AppSettings.currentSchemaVersion,
           hotkey.caseInsensitiveCompare("Ctrl+Alt+Space") == .orderedSame {
            migratedHotkey = AppSettings.defaultHotkey
        } else {
            migratedHotkey = hotkey
        }

        let gesture = HotkeyGesture.parse(migratedHotkey) ?? .defaultGesture

        return AppSettings(
            schemaVersion: AppSettings.currentSchemaVersion,
            preferredMicrophoneDeviceId: preferredMicrophoneDeviceId.trimmingCharacters(in: .whitespacesAndNewlines),
            hotkey: gesture.settingString,
            customVocabulary: customVocabulary.trimmingCharacters(in: .whitespacesAndNewlines),
            isTopmost: isTopmost,
            orbOpacityPercent: min(max(orbOpacityPercent, 35), 100),
            guidanceOpacityPercent: min(max(guidanceOpacityPercent, 40), 100),
            guidanceTemplate: DocumentTemplate(rawValue: guidanceTemplate.rawValue) ?? .auto,
            windowLeft: windowLeft,
            windowTop: windowTop,
            isExpanded: isExpanded
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case preferredMicrophoneDeviceId
        case hotkey
        case customVocabulary
        case isTopmost
        case orbOpacityPercent
        case guidanceOpacityPercent
        case guidanceTemplate
        case windowLeft
        case windowTop
        case isExpanded
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? AppSettings.currentSchemaVersion
        self.preferredMicrophoneDeviceId = try container.decodeIfPresent(String.self, forKey: .preferredMicrophoneDeviceId)
            ?? ""
        self.hotkey = try container.decodeIfPresent(String.self, forKey: .hotkey)
            ?? AppSettings.defaultHotkey
        self.customVocabulary = try container.decodeIfPresent(String.self, forKey: .customVocabulary)
            ?? AppSettings.defaultCustomVocabulary
        self.isTopmost = try container.decodeIfPresent(Bool.self, forKey: .isTopmost) ?? true
        self.orbOpacityPercent = try container.decodeIfPresent(Double.self, forKey: .orbOpacityPercent) ?? 78
        self.guidanceOpacityPercent = try container.decodeIfPresent(Double.self, forKey: .guidanceOpacityPercent) ?? 68
        self.guidanceTemplate = try container.decodeIfPresent(DocumentTemplate.self, forKey: .guidanceTemplate)
            ?? .auto
        self.windowLeft = try container.decodeIfPresent(Double.self, forKey: .windowLeft)
        self.windowTop = try container.decodeIfPresent(Double.self, forKey: .windowTop)
        self.isExpanded = try container.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? true
    }
}
