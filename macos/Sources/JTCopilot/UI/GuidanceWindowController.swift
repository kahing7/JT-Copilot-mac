import AppKit
import SwiftUI

@MainActor
final class GuidanceWindowController: NSWindowController {
    private static let panelSize = NSSize(
        width: GlassMetrics.panelWidth,
        height: GlassMetrics.panelHeight
    )
    fileprivate static let shadowInset: CGFloat = 24
    private static let windowSize = NSSize(
        width: panelSize.width + shadowInset * 2,
        height: panelSize.height + shadowInset * 2
    )
    private static let topMargin: CGFloat = 12

    private let model: AppModel
    private var hasPositionedPanel = false

    init(model: AppModel) {
        self.model = model

        let panel = GuidancePanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
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
        let rootView = GuidanceView(model: model)
            .padding(Self.shadowInset)
            .frame(width: Self.windowSize.width, height: Self.windowSize.height)
            .background(Color.clear)
        let hostingView = GuidanceHostingView(rootView: rootView)
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

        DispatchQueue.main.async { [weak self] in
            guard let panel = self?.window,
                  let contentView = panel.contentView else {
                return
            }
            let point = NSPoint(
                x: panel.frame.width * 0.65,
                y: panel.frame.height - Self.shadowInset - 21
            )
            let hitView = contentView.hitTest(point)
            NSLog("JT Copilot: guidance header hit=%@", String(describing: hitView))
        }
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
        let y = visible.maxY
            - size.height
            + Self.shadowInset
            - Self.topMargin

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private final class GuidanceHostingView<Content: View>: NSHostingView<Content> {
    private let interactiveInset = GuidanceWindowController.shadowInset

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let interactiveBounds = bounds.insetBy(
            dx: interactiveInset,
            dy: interactiveInset
        )
        guard interactiveBounds.contains(point) else { return nil }
        return super.hitTest(point)
    }
}

private final class GuidancePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
