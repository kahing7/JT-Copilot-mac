import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import JTCopilotCore

/// 全局快捷键监听。使用 CGEventTap，因此需要“辅助功能”权限。
/// 支持与 Windows 版相同的“多键同时按下”组合，如 Ctrl+Shift+J+T。
final class HotkeyService {
    static let syntheticEventMarker: Int64 = 0x4A54_4350

    var onPressed: (() -> Void)?
    var onCancelRequested: (() -> Void)?

    var captureEscape = false
    private(set) var gesture = HotkeyGesture.defaultGesture

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pressedKeyCodes = Set<UInt16>()
    private var triggerDown = false

    var isRunning: Bool {
        eventTap != nil
    }

    func start(gesture: HotkeyGesture) throws {
        self.gesture = gesture

        if isRunning {
            return
        }

        guard AXIsProcessTrusted() else {
            throw permissionError()
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let service = Unmanaged<HotkeyService>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            return service.handleEvent(proxy: proxy, type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw permissionError()
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func reconfigure(gesture: HotkeyGesture) throws {
        self.gesture = gesture
        if !isRunning {
            try start(gesture: gesture)
        }
    }

    func stop() {
        triggerDown = false
        pressedKeyCodes.removeAll()

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == HotkeyService.syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }

        if shouldBypassForInAppDialog() {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .keyDown:
            pressedKeyCodes.insert(keyCode)

            if keyCode == 0x35, captureEscape {
                triggerDown = false
                onCancelRequested?()
                return nil
            }

            if isGestureKey(keyCode), requiredModifiersSatisfied(event.flags) {
                if !triggerDown, allGestureKeysPressed() {
                    triggerDown = true
                    onPressed?()
                }
                return nil
            }

        case .keyUp:
            pressedKeyCodes.remove(keyCode)
            if triggerDown, isGestureKey(keyCode) || HotkeyKeyCatalog.isModifierKeyCode(keyCode) {
                triggerDown = false
            }

        case .flagsChanged:
            if triggerDown, !requiredModifiersSatisfied(event.flags) {
                triggerDown = false
            }

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func requiredModifiersSatisfied(_ flags: CGEventFlags) -> Bool {
        if gesture.modifiers.contains(.control), !flags.contains(.maskControl) {
            return false
        }
        if gesture.modifiers.contains(.shift), !flags.contains(.maskShift) {
            return false
        }
        if gesture.modifiers.contains(.option), !flags.contains(.maskAlternate) {
            return false
        }
        if gesture.modifiers.contains(.command), !flags.contains(.maskCommand) {
            return false
        }
        return true
    }

    private func isGestureKey(_ keyCode: UInt16) -> Bool {
        gesture.macKeyCodes.contains(keyCode)
    }

    private func allGestureKeysPressed() -> Bool {
        gesture.macKeyCodes.allSatisfy { pressedKeyCodes.contains($0) }
    }

    private func shouldBypassForInAppDialog() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        return frontmost.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    private func permissionError() -> NSError {
        NSError(domain: "JTCopilot.Hotkey", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "无法安装全局键盘监听。请在系统设置 → 隐私与安全性 → 辅助功能中允许 JT Copilot，必要时也允许“输入监控”。"
        ])
    }
}
