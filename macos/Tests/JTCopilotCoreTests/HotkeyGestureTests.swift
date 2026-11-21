import XCTest
@testable import JTCopilotCore

final class HotkeyGestureTests: XCTestCase {
    func testDefaultUsesRequestedFourKeyChord() {
        XCTAssertEqual("Ctrl+Shift+J+T", HotkeyGesture.defaultGesture.settingString)
        XCTAssertEqual("Ctrl + Shift + J + T", HotkeyGesture.defaultGesture.displayText)
    }

    func testParseNormalizesModifierAndKeyOrder() {
        let parsed = HotkeyGesture.parseOrDefault("Shift+Control+T+J")
        XCTAssertEqual("Ctrl+Shift+T+J", parsed.settingString)
    }

    func testParseRejectsUnsafeOrInvalidGestures() {
        let invalidValues = ["T", "Shift+T", "Ctrl+Escape", "Ctrl+", "Ctrl+NotAKey", " "]
        for value in invalidValues {
            XCTAssertNil(HotkeyGesture.parse(value), value)
            XCTAssertEqual(HotkeyGesture.defaultGesture, HotkeyGesture.parseOrDefault(value), value)
        }
    }

    func testCreateAllowsMultipleNonModifierKeys() {
        let created = HotkeyGesture.create(
            modifiers: [.control, .option],
            keyLabels: ["J", "T"]
        )
        XCTAssertNotNil(created)
        XCTAssertEqual("Ctrl+Alt+J+T", created?.settingString)
    }

    func testMacDisplayTextUsesSymbols() {
        XCTAssertEqual("⌃⇧J T", HotkeyGesture.defaultGesture.macDisplayText)
    }

    func testCreateRejectsModifierOnlyAndEscape() {
        XCTAssertNil(HotkeyGesture.create(modifiers: [.control], keyLabels: []))
        XCTAssertNil(HotkeyGesture.create(modifiers: [.shift], keyLabels: ["T"]))
        XCTAssertNil(HotkeyGesture.create(modifiers: [.control], keyLabels: ["Escape"]))
    }
}
