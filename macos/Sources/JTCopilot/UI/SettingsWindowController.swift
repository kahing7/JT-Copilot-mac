import AppKit
import SwiftUI
import JTCopilotCore

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel
    private var keyMonitor: Any?
    private var permissionTimer: Timer?

    init(model: AppModel) {
        self.model = model

        let window = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 620),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.animationBehavior = .none
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: SettingsView(model: model) { [weak self] in
                self?.closeSettings()
            }
        )
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showSettings() {
        model.refreshPermissions()
        model.refreshAudioDevices(preferredID: model.currentSettings.preferredMicrophoneDeviceId)
        installKeyMonitor()
        startPermissionTimer()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func closeSettings() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        removeKeyMonitor()
        stopPermissionTimer()
        if model.isCapturingHotkey {
            model.cancelHotkeyCapture()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if model.isCapturingHotkey {
            model.cancelHotkeyCapture()
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged]
        ) { [weak self] event in
            var swallow = false
            MainActor.assumeIsolated {
                swallow = self?.handleKeyEvent(event) ?? false
            }
            return swallow ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard model.isCapturingHotkey else { return false }

        let modifiers = HotkeyModifiers(eventFlags: event.modifierFlags)

        switch event.type {
        case .keyDown:
            if event.keyCode == 53 {
                model.cancelHotkeyCapture()
                return true
            }

            model.previewHotkey(modifiers: modifiers, keyCode: event.keyCode)
            return true

        case .keyUp:
            if HotkeyKeyCatalog.isModifierKeyCode(event.keyCode) {
                return true
            }

            model.finishHotkeyCapture(modifiers: modifiers, keyCode: event.keyCode)
            return true

        case .flagsChanged:
            model.previewHotkey(modifiers: modifiers, keyCode: event.keyCode)
            return true

        default:
            return false
        }
    }

    private func startPermissionTimer() {
        guard permissionTimer == nil else { return }

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.refreshPermissions()
            }
        }
    }

    private func stopPermissionTimer() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }
}

private final class SettingsPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension HotkeyModifiers {
    init(eventFlags: NSEvent.ModifierFlags) {
        var modifiers: HotkeyModifiers = []
        if eventFlags.contains(.control) { modifiers.insert(.control) }
        if eventFlags.contains(.shift) { modifiers.insert(.shift) }
        if eventFlags.contains(.option) { modifiers.insert(.option) }
        if eventFlags.contains(.command) { modifiers.insert(.command) }
        self = modifiers
    }
}
