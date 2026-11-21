import AppKit
import SwiftUI

@MainActor
final class OrbWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel
    private var saveTimer: Timer?

    private static let orbSize: CGFloat = 72

    init(model: AppModel) {
        self.model = model

        let panel = OrbPanel(
            contentRect: NSRect(x: 0, y: 0, width: 72, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init(window: panel)

        panel.isFloatingPanel = true
        panel.level = model.isTopmost ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.delegate = self
        let hostingView = NSHostingView(rootView: OrbView(model: model))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        restorePosition()

        model.onTopmostChanged = { [weak self] value in
            MainActor.assumeIsolated {
                self?.window?.level = value ? .floating : .normal
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showOrb() {
        window?.orderFrontRegardless()
    }

    func windowDidMove(_ notification: Notification) {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let frame = self.window?.frame else { return }
                self.model.saveOrbOrigin(x: frame.origin.x, y: frame.origin.y)
            }
        }
    }

    private func restorePosition() {
        let settings = model.currentSettings
        let size = OrbWindowController.orbSize

        if let left = settings.windowLeft, let top = settings.windowTop {
            let candidate = NSRect(x: left, y: top, width: size, height: size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(candidate) }) {
                window?.setFrameOrigin(NSPoint(x: left, y: top))
                return
            }
        }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        window?.setFrameOrigin(
            NSPoint(x: visible.maxX - size - 24, y: visible.minY + 24)
        )
    }
}

private final class OrbPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
