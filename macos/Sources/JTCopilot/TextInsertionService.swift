import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import JTCopilotCore

/// 通过 Accessibility + CGEvent 向当前编辑器写入文字。
/// 实时部分使用 Unicode 键盘事件；整段稳定文字和最终替换使用剪贴板粘贴。
@MainActor
final class TextInsertionService {
    struct Target {
        let processIdentifier: pid_t
        let applicationName: String
        let element: AXUIElement?
        let startLocation: Int?

        var displayName: String {
            applicationName
        }
    }

    private let syntheticMarker = HotkeyService.syntheticEventMarker

    // MARK: - Target capture

    func captureTarget() -> Target? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }

        var focusedElement: AXUIElement?
        if let element = currentFocusedElement() {
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)

            if pid == app.processIdentifier {
                if isSecureTextField(element) {
                    return nil
                }
                focusedElement = element
            }
        }

        let range = focusedElement.flatMap { selectedTextRange($0) }
        let name = app.localizedName ?? "未知应用"

        return Target(
            processIdentifier: app.processIdentifier,
            applicationName: name,
            element: focusedElement,
            startLocation: range?.location
        )
    }

    func isActive(_ target: Target) -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        guard frontmost.processIdentifier == target.processIdentifier else {
            return false
        }

        guard frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return false
        }

        if let focused = currentFocusedElement(), isSecureTextField(focused) {
            return false
        }

        if let element = target.element {
            var pid: pid_t = 0
            if AXUIElementGetPid(element, &pid) == .success, pid != target.processIdentifier {
                return false
            }
        }

        return true
    }

    private func currentFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedReference: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedReference
        ) == .success,
              let focusedReference,
              CFGetTypeID(focusedReference) == AXUIElementGetTypeID() else {
            return nil
        }

        return (focusedReference as! AXUIElement)
    }

    // MARK: - Insertion

    func insert(_ text: String, target: Target) async -> TextInsertionResult {
        guard !text.isEmpty else { return .succeeded }
        guard isActive(target) else {
            return TextInsertionResult(success: false, message: "焦点已离开原编辑器，文字未自动写入。")
        }

        return await replaceSelectionWithPaste(text, target: target)
    }

    func updateLiveDraft(
        previous: String,
        current: String,
        target: Target
    ) async -> TextInsertionResult {
        guard isActive(target) else {
            return TextInsertionResult(success: false, message: "焦点已离开原编辑器，实时文字暂停写入。")
        }

        let diff = LiveTextDiffCalculator.calculate(previous: previous, current: current)

        if diff.backspaceCount > 0 {
            sendBackspaces(diff.backspaceCount)
        }

        if !diff.textToInsert.isEmpty {
            sendUnicodeText(diff.textToInsert)
        }

        try? await Task.sleep(nanoseconds: 12_000_000)
        return .succeeded
    }

    func replaceSessionText(
        expected: String,
        replacement: String,
        target: Target
    ) async -> TextInsertionResult {
        guard isActive(target) else {
            return TextInsertionResult(success: false, message: "焦点已离开原编辑器，优化全文未自动替换。")
        }

        if let element = target.element,
           let startLocation = target.startLocation,
           selectSessionRange(
               element: element,
               startLocation: startLocation,
               expected: expected,
               target: target
           ) {
            return await replaceSelectionWithPaste(replacement, target: target)
        }

        return replaceWithKeyboardFallback(
            expected: expected,
            replacement: replacement,
            target: target
        )
    }

    // MARK: - Accessibility ranges

    private func selectSessionRange(
        element: AXUIElement,
        startLocation: Int,
        expected: String,
        target: Target
    ) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == target.processIdentifier else {
            return false
        }

        guard let current = selectedTextRange(element), current.location >= startLocation else {
            return false
        }

        let range = NSRange(location: startLocation, length: current.location - startLocation)
        guard range.length > 0,
              let existing = stringForRange(element, range: range),
              isEquivalent(existing, expected) else {
            return false
        }

        var cfRange = CFRange(location: range.location, length: range.length)
        guard let axValue = AXValueCreate(.cfRange, &cfRange) else {
            return false
        }

        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            axValue as CFTypeRef
        ) == .success
    }

    private func selectedTextRange(_ element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }

        return NSRange(location: range.location, length: range.length)
    }

    private func stringForRange(_ element: AXUIElement, range: NSRange) -> String? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let axRange = AXValueCreate(.cfRange, &cfRange) else {
            return nil
        }

        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            axRange as CFTypeRef,
            &value
        ) == .success,
              let value else {
            return nil
        }

        return value as? String
    }

    private func isSecureTextField(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSubroleAttribute as CFString,
            &value
        ) == .success,
              let value else {
            return false
        }

        return (value as? String) == "AXSecureTextField"
    }

    // MARK: - Keyboard events

    private func sendUnicodeText(_ text: String) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let units = Array(text.utf16)
        var index = 0

        while index < units.count {
            var end = min(index + 20, units.count)
            if end < units.count,
               end > index,
               (0xD800...0xDBFF).contains(units[end - 1]) {
                end -= 1
            }

            guard end > index else { break }
            postUnicodeChunk(Array(units[index..<end]), source: source)
            index = end
        }
    }

    private func postUnicodeChunk(_ units: [UniChar], source: CGEventSource) {
        guard !units.isEmpty else { return }

        units.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }

            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: baseAddress)
                down.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
                down.post(tap: .cghidEventTap)
            }

            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: baseAddress)
                up.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
                up.post(tap: .cghidEventTap)
            }
        }
    }

    private func sendBackspaces(_ count: Int) {
        guard count > 0, let source = CGEventSource(stateID: .hidSystemState) else { return }

        for index in 0..<count {
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true) {
                down.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
                down.post(tap: .cghidEventTap)
            }

            if let up = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false) {
                up.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
                up.post(tap: .cghidEventTap)
            }

            if index % 64 == 63 {
                usleep(1_000)
            }
        }
    }

    private func sendPasteShortcut() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        if let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) {
            down.flags = .maskCommand
            down.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            down.post(tap: .cghidEventTap)
        }

        if let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) {
            up.flags = .maskCommand
            up.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            up.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Clipboard insertion

    private func replaceSelectionWithPaste(_ text: String, target: Target) async -> TextInsertionResult {
        guard isActive(target) else {
            return TextInsertionResult(success: false, message: "焦点已离开原编辑器，文字未自动写入。")
        }

        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems
        let savedString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        do {
            try await Task.sleep(nanoseconds: 70_000_000)

            guard isActive(target) else {
                restorePasteboard(items: savedItems, string: savedString)
                return TextInsertionResult(success: false, message: "写入前焦点已变化，文字未自动输入。")
            }

            sendPasteShortcut()
            try await Task.sleep(nanoseconds: 450_000_000)
            restorePasteboard(items: savedItems, string: savedString)
            return .succeeded
        } catch {
            restorePasteboard(items: savedItems, string: savedString)
            return TextInsertionResult(success: false, message: "文字写入失败：\(error.localizedDescription)")
        }
    }

    private func restorePasteboard(items: [NSPasteboardItem]?, string: String?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let items, !items.isEmpty {
            let writings: [NSPasteboardWriting] = items.map { $0 }
            if pasteboard.writeObjects(writings) {
                return
            }
        }

        if let string {
            pasteboard.setString(string, forType: .string)
        }
    }

    private func replaceWithKeyboardFallback(
        expected: String,
        replacement: String,
        target: Target
    ) -> TextInsertionResult {
        guard isActive(target) else {
            return TextInsertionResult(success: false, message: "焦点已离开原编辑器，优化全文未自动替换。")
        }

        let count = expected.count
        guard count > 0 else {
            return TextInsertionResult(success: false, message: "本次会话没有可替换的文字。")
        }

        sendBackspaces(count)
        sendUnicodeText(replacement)
        return .succeeded
    }

    private func isEquivalent(_ actual: String, _ expected: String) -> Bool {
        func normalize(_ value: String) -> String {
            value.replacingOccurrences(of: "\r\n", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return normalize(actual) == normalize(expected)
    }
}
