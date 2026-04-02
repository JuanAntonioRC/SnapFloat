import AppKit

// MARK: – Stroke

private struct Stroke {
    let color: NSColor
    var points: [NSPoint]
}

// MARK: – Canvas view

final class DrawingCanvasView: NSView {
    var strokeColor: NSColor = .systemRed
    private var strokes: [Stroke] = []
    private var active: Stroke?
    let image: NSImage

    init(image: NSImage, frame: NSRect) {
        self.image = image
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: Draw

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds)
        strokes.forEach { paint($0) }
        if let a = active { paint(a) }
    }

    private func paint(_ s: Stroke) {
        guard !s.points.isEmpty else { return }
        s.color.setStroke()
        s.color.setFill()
        if s.points.count == 1 {
            let r = NSRect(x: s.points[0].x - 2, y: s.points[0].y - 2, width: 4, height: 4)
            NSBezierPath(ovalIn: r).fill()
            return
        }
        let path = NSBezierPath()
        path.move(to: s.points[0])
        s.points.dropFirst().forEach { path.line(to: $0) }
        path.lineWidth = 3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        active = Stroke(color: strokeColor, points: [convert(event.locationInWindow, from: nil)])
    }
    override func mouseDragged(with event: NSEvent) {
        active?.points.append(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if let s = active { strokes.append(s) }
        active = nil
        needsDisplay = true
    }

    // MARK: Actions

    func undo() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
        needsDisplay = true
    }

    /// Returns the image + strokes composited at original image resolution.
    func compositeImage() -> NSImage {
        let out = NSImage(size: image.size)
        out.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        let sx = image.size.width  / bounds.width
        let sy = image.size.height / bounds.height
        for s in strokes {
            guard !s.points.isEmpty else { continue }
            s.color.setStroke()
            s.color.setFill()
            if s.points.count == 1 {
                let p = NSPoint(x: s.points[0].x * sx, y: s.points[0].y * sy)
                let r = NSRect(x: p.x - 2*sx, y: p.y - 2*sy, width: 4*sx, height: 4*sy)
                NSBezierPath(ovalIn: r).fill()
                continue
            }
            let path = NSBezierPath()
            path.move(to: NSPoint(x: s.points[0].x * sx, y: s.points[0].y * sy))
            for pt in s.points.dropFirst() {
                path.line(to: NSPoint(x: pt.x * sx, y: pt.y * sy))
            }
            path.lineWidth = 3 * sx
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
        out.unlockFocus()
        return out
    }
}

// MARK: – Color dot

private final class ColorDot: NSView {
    let color: NSColor
    var isSelected = false { didSet { needsDisplay = true } }
    var onTap: (() -> Void)?

    init(_ color: NSColor) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = isSelected ? 4 : 2
        let fill = NSBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset))
        color.setFill()
        fill.fill()
        if isSelected {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 2
            NSColor.white.setStroke()
            ring.stroke()
        }
    }
    override func mouseDown(with event: NSEvent) { onTap?() }
}

// MARK: – Annotation window controller

final class AnnotationWindowController: NSWindowController {
    private static var instance: AnnotationWindowController?
    private var canvas: DrawingCanvasView!
    private var colorDots: [ColorDot] = []

    // MARK: Public

    static func show(image: NSImage) {
        DispatchQueue.main.async {
            instance?.window?.close()
            instance = AnnotationWindowController(image: image)
            instance?.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: Init

    init(image: NSImage) {
        let toolbarH: CGFloat = 52

        // Scale to fit in 900×700, upscale tiny captures up to 2×
        let maxW: CGFloat = 900, maxH: CGFloat = 700
        let scale = min(maxW / image.size.width, maxH / image.size.height)
        let cw = image.size.width * scale
        let ch = image.size.height * scale

        let screen = NSScreen.main!
        let winSize = NSSize(width: cw, height: ch + toolbarH)
        let origin = NSPoint(
            x: (screen.visibleFrame.width  - winSize.width)  / 2 + screen.visibleFrame.minX,
            y: (screen.visibleFrame.height - winSize.height) / 2 + screen.visibleFrame.minY
        )

        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: winSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "SnapFloat — Anotar"
        win.isReleasedWhenClosed = false
        win.level = .floating

        super.init(window: win)
        win.delegate = self

        guard let content = win.contentView else { return }

        canvas = DrawingCanvasView(
            image: image,
            frame: NSRect(x: 0, y: toolbarH, width: cw, height: ch)
        )
        content.addSubview(canvas)
        buildToolbar(in: content, w: cw, h: toolbarH)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Toolbar

    private func buildToolbar(in parent: NSView, w: CGFloat, h: CGFloat) {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
        parent.addSubview(bar)

        let palette: [NSColor] = [
            .systemRed, .systemOrange, .systemYellow,
            .systemGreen, .systemBlue, .white, .black
        ]
        let dotW: CGFloat = 26, gap: CGFloat = 8
        var x: CGFloat = 14

        for (i, color) in palette.enumerated() {
            let dot = ColorDot(color)
            dot.frame.origin = NSPoint(x: x, y: (h - dotW) / 2)
            dot.onTap = { [weak self] in
                guard let self else { return }
                self.canvas.strokeColor = color
                self.colorDots.forEach { $0.isSelected = false }
                self.colorDots[i].isSelected = true
            }
            bar.addSubview(dot)
            colorDots.append(dot)
            x += dotW + gap
        }
        colorDots.first?.isSelected = true
        x += 12

        let undoBtn = sysBtn(title: "↩ Deshacer", width: 100)
        undoBtn.frame.origin = NSPoint(x: x, y: (h - 26) / 2)
        undoBtn.target = self
        undoBtn.action = #selector(didUndo)
        bar.addSubview(undoBtn)
        x += undoBtn.frame.width + 8

        let copyBtn = sysBtn(title: "✓ Copiar", width: 90)
        copyBtn.frame.origin = NSPoint(x: x, y: (h - 26) / 2)
        copyBtn.target = self
        copyBtn.action = #selector(didCopy)
        bar.addSubview(copyBtn)
    }

    private func sysBtn(title: String, width: CGFloat) -> NSButton {
        let b = NSButton(frame: NSRect(x: 0, y: 0, width: width, height: 26))
        b.title = title
        b.bezelStyle = .rounded
        b.font = .systemFont(ofSize: 12, weight: .medium)
        return b
    }

    @objc private func didUndo() { canvas.undo() }

    @objc private func didCopy() {
        let img = canvas.compositeImage()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
        SettingsManager.saveToDiskIfNeeded(img)
        window?.close()
    }
}

extension AnnotationWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        AnnotationWindowController.instance = nil
    }
}
