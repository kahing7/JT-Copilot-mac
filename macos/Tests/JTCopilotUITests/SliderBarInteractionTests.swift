import AppKit
import XCTest
@testable import JTCopilot

@MainActor
final class SliderBarInteractionTests: XCTestCase {
    func testMouseDragUpdatesValueContinuously() {
        let view = SliderBarAppKitView(frame: NSRect(x: 0, y: 0, width: 200, height: 18))
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view

        var values: [Double] = []
        view.onChange = { values.append($0) }

        view.mouseDown(with: mouseEvent(type: .leftMouseDown, x: 20, in: window))
        view.mouseDragged(with: mouseEvent(type: .leftMouseDragged, x: 100, in: window))
        view.mouseUp(with: mouseEvent(type: .leftMouseUp, x: 190, in: window))

        XCTAssertEqual(values.count, 3)
        XCTAssertLessThan(values[0], values[1])
        XCTAssertLessThan(values[1], values[2])
        XCTAssertGreaterThan(values[2], 95)
    }

    private func mouseEvent(type: NSEvent.EventType, x: CGFloat, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: x, y: window.contentView?.bounds.midY ?? 0),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }
}
