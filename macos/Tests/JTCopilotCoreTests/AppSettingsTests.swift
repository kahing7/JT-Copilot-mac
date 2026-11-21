import XCTest
@testable import JTCopilotCore

final class AppSettingsTests: XCTestCase {
    func testNormalizeRestoresDefaultHotkeyAndTrimsMicrophoneId() {
        var settings = AppSettings()
        settings.hotkey = " "
        settings.preferredMicrophoneDeviceId = "  2  "

        let normalized = settings.normalized()

        XCTAssertEqual(AppSettings.defaultHotkey, normalized.hotkey)
        XCTAssertEqual("2", normalized.preferredMicrophoneDeviceId)
        XCTAssertEqual(AppSettings.currentSchemaVersion, normalized.schemaVersion)
    }

    func testNormalizeMigratesLegacyDefaultHotkey() {
        var settings = AppSettings()
        settings.schemaVersion = 1
        settings.hotkey = "Ctrl+Alt+Space"

        let normalized = settings.normalized()

        XCTAssertEqual("Ctrl+Shift+J+T", normalized.hotkey)
        XCTAssertEqual(AppSettings.currentSchemaVersion, normalized.schemaVersion)
    }

    func testNormalizeReplacesInvalidHotkeyWithDefault() {
        var settings = AppSettings()
        settings.hotkey = "Shift+T"
        XCTAssertEqual(AppSettings.defaultHotkey, settings.normalized().hotkey)
    }

    func testNormalizeClampsGlassOpacityRanges() {
        var settings = AppSettings()
        settings.orbOpacityPercent = 5
        settings.guidanceOpacityPercent = 130

        let normalized = settings.normalized()

        XCTAssertEqual(35, normalized.orbOpacityPercent)
        XCTAssertEqual(100, normalized.guidanceOpacityPercent)
    }

    func testDecodeRejectsUnknownGuidanceTemplate() throws {
        let json = #"{"schemaVersion":3,"guidanceTemplate":999}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(DocumentTemplate.auto, settings.guidanceTemplate)
    }

    func testMissingFieldsFallBackToDefaults() throws {
        let json = #"{"hotkey":"Ctrl+Alt+Space"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(78, settings.orbOpacityPercent)
        XCTAssertEqual(DocumentTemplate.auto, settings.guidanceTemplate)
        XCTAssertTrue(settings.isTopmost)
    }

    func testEncodeDecodeRoundTrip() throws {
        let settings = AppSettings(isTopmost: false, orbOpacityPercent: 55, guidanceTemplate: .prd)
        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)
        XCTAssertEqual(settings, decoded)
    }
}
