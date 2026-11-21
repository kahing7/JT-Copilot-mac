import AppKit
import SwiftUI

enum Theme {
    static let canvas = Color(hex: 0x0B1117)
    static let panel = Color(hex: 0x131C25)
    static let panelRaised = Color(hex: 0x1B2732)
    static let border = Color(hex: 0x2B3A47)
    static let textPrimary = Color(hex: 0xF3F7FA)
    static let textSecondary = Color(hex: 0x9BABB8)
    static let textTertiary = Color(hex: 0x70808D)
    static let accent = Color(hex: 0x2DD4BF)
    static let accentStrong = Color(hex: 0x14B8A6)
    static let accentInk = Color(hex: 0x042F2E)
    static let danger = Color(hex: 0xFB7185)
    static let warning = Color(hex: 0xF4B860)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.state = .active
    }
}

/// 使用屏幕坐标拖动窗口，避免窗口移动后局部手势坐标变化造成跟随迟滞。
private final class WindowDragProbeView: NSView {
    var onClick: (() -> Void)?
    var clampsToVisibleFrame = false
    var usesNativeWindowDrag = false

    private static let dragThreshold: CGFloat = 3

    private var mouseDownLocation: NSPoint?
    private var initialWindowOrigin: NSPoint?
    private var didDrag = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let event = NSApp.currentEvent {
            if event.type == .rightMouseDown || event.type == .rightMouseUp {
                return nil
            }
            if event.type == .leftMouseDown && event.modifierFlags.contains(.control) {
                return nil
            }
        }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if usesNativeWindowDrag {
            NSLog("JT Copilot: native window drag started")
            window.performDrag(with: event)
            return
        }

        window.makeKey()
        NSLog("JT Copilot: window drag mouseDown")
        mouseDownLocation = window.convertPoint(toScreen: event.locationInWindow)
        initialWindowOrigin = window.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let window,
            let mouseDownLocation,
            let initialWindowOrigin
        else {
            return
        }

        let mouseLocation = window.convertPoint(toScreen: event.locationInWindow)
        let deltaX = mouseLocation.x - mouseDownLocation.x
        let deltaY = mouseLocation.y - mouseDownLocation.y

        if !didDrag {
            guard hypot(deltaX, deltaY) >= Self.dragThreshold else { return }
            didDrag = true
            NSLog("JT Copilot: window drag started")
            NSCursor.closedHand.push()
        }

        var origin = NSPoint(
            x: initialWindowOrigin.x + deltaX,
            y: initialWindowOrigin.y + deltaY
        )

        if clampsToVisibleFrame {
            origin = clampedOrigin(origin, for: window, mouseLocation: mouseLocation)
        }

        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        let wasClick = !didDrag
        if didDrag {
            NSCursor.pop()
        }

        mouseDownLocation = nil
        initialWindowOrigin = nil
        didDrag = false

        if wasClick {
            onClick?()
        }
    }

    private func clampedOrigin(
        _ origin: NSPoint,
        for window: NSWindow,
        mouseLocation: NSPoint
    ) -> NSPoint {
        let screen = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return origin }

        let size = window.frame.size
        let maxX = max(visible.minX, visible.maxX - size.width)
        let maxY = max(visible.minY, visible.maxY - size.height)

        return NSPoint(
            x: min(max(origin.x, visible.minX), maxX),
            y: min(max(origin.y, visible.minY), maxY)
        )
    }
}

struct WindowDragArea: NSViewRepresentable {
    var clampsToVisibleFrame = false
    var usesNativeWindowDrag = false
    var onClick: (() -> Void)?

    func makeNSView(context: Context) -> NSView {
        let view = WindowDragProbeView(frame: .zero)
        view.clampsToVisibleFrame = clampsToVisibleFrame
        view.usesNativeWindowDrag = usesNativeWindowDrag
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? WindowDragProbeView else { return }
        view.clampsToVisibleFrame = clampsToVisibleFrame
        view.usesNativeWindowDrag = usesNativeWindowDrag
        view.onClick = onClick
    }
}

struct FrostedBackground: View {
    var cornerRadius: CGFloat
    var tint: Color
    var material: NSVisualEffectView.Material = .hudWindow
    var blurOpacity: Double = 1

    var body: some View {
        ZStack {
            VisualEffectView(material: material)
                .opacity(blurOpacity)
            tint
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
    }
}

struct CommandButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(prominent ? Theme.accentInk : Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(prominent
                          ? Theme.accentStrong.opacity(configuration.isPressed ? 0.8 : 1)
                          : Theme.panelRaised.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.border.opacity(prominent ? 0 : 1), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct CloseIconButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.clear)
        )
        .help("关闭")
    }
}

struct DarkFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.panelRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

extension View {
    func darkField() -> some View {
        modifier(DarkFieldModifier())
    }
}

struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
    }
}
