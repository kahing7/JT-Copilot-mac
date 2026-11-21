import AppKit
import SwiftUI

struct SliderBar: View {
    @Binding var value: Double
    var tint: Color
    var accessibilityLabel: String

    @Environment(\.glassTokens) private var tokens

    var body: some View {
        SliderBarRepresentable(
            value: $value,
            tint: NSColor(tint),
            trackColor: NSColor(tokens.sliderTrack),
            accessibilityLabel: accessibilityLabel
        )
        .frame(height: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(Int(value.rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(value + 5, 100)
            case .decrement:
                value = max(value - 5, 0)
            @unknown default:
                break
            }
        }
    }
}

private struct SliderBarRepresentable: NSViewRepresentable {
    @Binding var value: Double
    var tint: NSColor
    var trackColor: NSColor
    var accessibilityLabel: String

    func makeNSView(context: Context) -> SliderBarAppKitView {
        let view = SliderBarAppKitView()
        view.onChange = { newValue in
            value = newValue
        }
        update(view)
        return view
    }

    func updateNSView(_ nsView: SliderBarAppKitView, context: Context) {
        update(nsView)
    }

    private func update(_ view: SliderBarAppKitView) {
        view.value = min(max(value, 0), 100)
        view.tintColor = tint
        view.trackColor = trackColor
        view.accessibilityLabel = accessibilityLabel
    }
}

final class SliderBarAppKitView: NSView {
    var onChange: ((Double) -> Void)?
    var tintColor = NSColor.systemOrange
    var trackColor = NSColor.white.withAlphaComponent(0.14)
    var accessibilityLabel = "滑杆" {
        didSet {
            updateAccessibilityValue()
        }
    }

    var value: Double = 0 {
        didSet {
            value = min(max(value, 0), 100)
            needsDisplay = true
            updateAccessibilityValue()
        }
    }

    private let thumbSize: CGFloat = 14
    private var isDragging = false

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trackHeight: CGFloat = 8
        let trackY = bounds.midY - trackHeight / 2
        let trackRect = NSRect(
            x: 0,
            y: trackY,
            width: bounds.width,
            height: trackHeight
        )
        trackColor.setFill()
        NSBezierPath(
            roundedRect: trackRect,
            xRadius: trackHeight / 2,
            yRadius: trackHeight / 2
        ).fill()

        let usableWidth = max(bounds.width - thumbSize, 1)
        let progress = CGFloat(value / 100)
        let fillWidth = max(thumbSize / 2, thumbSize / 2 + usableWidth * progress)
        tintColor.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 0, y: trackY, width: fillWidth, height: trackHeight),
            xRadius: trackHeight / 2,
            yRadius: trackHeight / 2
        ).fill()

        let thumbRect = NSRect(
            x: usableWidth * progress,
            y: bounds.midY - thumbSize / 2,
            width: thumbSize,
            height: thumbSize
        )
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.white.withAlphaComponent(0.96).setFill()
        NSBezierPath(ovalIn: thumbRect).fill()
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        window?.makeFirstResponder(self)
        updateValue(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        updateValue(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        updateValue(with: event)
        isDragging = false
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            setValue(value - 1)
        case 124:
            setValue(value + 1)
        case 125:
            setValue(value - 5)
        case 126:
            setValue(value + 5)
        case 115:
            setValue(0)
        case 119:
            setValue(100)
        default:
            super.keyDown(with: event)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func updateValue(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let usableWidth = max(bounds.width - thumbSize, 1)
        let progress = min(max((location.x - thumbSize / 2) / usableWidth, 0), 1)
        setValue(Double(progress) * 100)
    }

    private func setValue(_ newValue: Double) {
        let clamped = min(max(newValue, 0), 100)
        guard abs(clamped - value) > 0.001 else { return }
        value = clamped
        onChange?(clamped)
    }

    private func updateAccessibilityValue() {
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityMinValue(0)
        setAccessibilityMaxValue(100)
        setAccessibilityValue(Int(value.rounded()))
    }
}
