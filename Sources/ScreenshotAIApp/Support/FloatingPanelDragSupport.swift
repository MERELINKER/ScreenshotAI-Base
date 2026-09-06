import AppKit
import SwiftUI

enum FloatingPanelDragMath {
    static func origin(from start: NSPoint, translation: CGSize) -> NSPoint {
        NSPoint(x: start.x + translation.width, y: start.y - translation.height)
    }
}

struct FloatingPanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NativeWindowDragHandle(frame: NSRect(x: 0, y: 0, width: 26, height: 28))
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class NativeWindowDragHandle: NSImageView {
    private var startOrigin: NSPoint?
    private var startMouse: NSPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "拖动悬浮窗")
        imageScaling = .scaleProportionallyDown
        contentTintColor = .secondaryLabelColor
        toolTip = "拖动悬浮窗"
        setAccessibilityLabel("拖动悬浮窗")
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        startOrigin = window?.frame.origin
        startMouse = NSEvent.mouseLocation
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let startOrigin, let startMouse else { return }
        let mouse = NSEvent.mouseLocation
        let translation = CGSize(width: mouse.x - startMouse.x, height: -(mouse.y - startMouse.y))
        window.setFrameOrigin(FloatingPanelDragMath.origin(from: startOrigin, translation: translation))
    }
    override func mouseUp(with event: NSEvent) {
        startOrigin = nil
        startMouse = nil
    }
}
