import AppKit

/// The view inside the capture overlay.
/// Uses a flipped coordinate system so (0,0) is the top-left of the screen.
final class CaptureOverlayView: NSView {

    /// The screen frame in global AppKit coords — used when converting to screen coords for capture.
    var screenFrame: NSRect = .zero

    private var startPoint: NSPoint?
    private var currentRect: NSRect?

    // MARK: – Coordinate system

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: – Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current else { return }

        // Semi-transparent dark overlay
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()

        guard let rect = currentRect, rect.width > 2, rect.height > 2 else { return }

        // Punch a transparent hole for the selected area
        ctx.compositingOperation = .clear
        rect.fill()
        ctx.compositingOperation = .sourceOver

        // Selection border
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1.0
        border.stroke()

        // Dimension label
        drawSizeLabel(for: rect)
    }

    private func drawSizeLabel(for rect: NSRect) {
        let label = String(format: "%.0f × %.0f", rect.width, rect.height)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.55)
        ]
        let size = label.size(withAttributes: attrs)
        let padding: CGFloat = 4
        var origin = NSPoint(x: rect.minX + 4, y: rect.minY - size.height - padding - 2)
        // Keep label inside the view
        if origin.y < 2 { origin.y = rect.maxY + 2 }
        let labelRect = NSRect(x: origin.x - padding, y: origin.y,
                               width: size.width + padding * 2, height: size.height + padding)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 3, yRadius: 3).fill()
        label.draw(at: NSPoint(x: origin.x, y: origin.y + padding / 2), withAttributes: attrs)
    }

    // MARK: – Mouse events

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = nil
        setNeedsDisplay(bounds)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        currentRect = rectFrom(start, current)
        setNeedsDisplay(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        let sel = rectFrom(start, current)
        startPoint = nil
        currentRect = nil

        guard sel.width > 5, sel.height > 5 else {
            CaptureOverlayWindow.dismiss()
            return
        }

        // Convert flipped-view rect → AppKit screen coords
        let screenRect = NSRect(
            x: screenFrame.origin.x + sel.origin.x,
            y: screenFrame.origin.y + (screenFrame.height - sel.origin.y - sel.height),
            width: sel.width,
            height: sel.height
        )

        CaptureOverlayWindow.dismiss()

        // Brief delay so the overlay window is fully gone before we grab pixels
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            ScreenCaptureManager.capture(rect: screenRect)
        }
    }

    // MARK: – Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            CaptureOverlayWindow.dismiss()
        }
    }

    // MARK: – Helpers

    private func rectFrom(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}
