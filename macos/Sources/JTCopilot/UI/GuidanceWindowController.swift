import AppKit
import SwiftUI

@MainActor
final class GuidanceWindowController: NSWindowController {
    private static let panelSize = NSSize(width: 820, height: 380)
    private static let topMargin: CGFloat = 12

    private let model: AppModel
    private var hasPositionedPanel = false

    init(model: AppModel) {
        self.model = model

        let panel = GuidancePanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init(window: panel)

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        let hostingView = NSHostingView(rootView: GuidanceView(model: model))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        model.onGuidanceVisibilityChanged = { [weak self] visible in
            MainActor.assumeIsolated {
                if visible {
                    self?.showGuidance()
                } else {
                    self?.hideGuidance()
                }
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showGuidance() {
        if !hasPositionedPanel {
            positionAtTopCenter()
            hasPositionedPanel = true
        }
        window?.orderFrontRegardless()
    }

    func hideGuidance() {
        window?.orderOut(nil)
    }

    private func positionAtTopCenter() {
        guard let panel = window else { return }

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let size = panel.frame.size
        let x = min(
            max(visible.midX - size.width / 2, visible.minX),
            visible.maxX - size.width
        )
        let y = visible.maxY - size.height - Self.topMargin

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private final class GuidancePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
