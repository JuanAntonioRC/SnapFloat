import AppKit

// MARK: – Tool enum

enum AnnotationTool: String, CaseIterable {
    case pen, line, arrow, rect, oval, text

    var icon: String {
        switch self {
        case .pen:   return "pencil.tip"
        case .line:  return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rect:  return "rectangle"
        case .oval:  return "oval"
        case .text:  return "textformat"
        }
    }

    var label: String {
        switch self {
        case .pen:   return "Pen"
        case .line:  return "Line"
        case .arrow: return "Arrow"
        case .rect:  return "Rectangle"
        case .oval:  return "Oval"
        case .text:  return "Text"
        }
    }
}

// MARK: – Annotation model

private struct Annotation {
    let tool: AnnotationTool
    let color: NSColor
    let lineWidth: CGFloat
    var points: [NSPoint]        // pen: all points; others: [origin, current]
    var text: String?            // only for .text
}

// MARK: – Arrow helpers

/// Draw an arrow with a clean triangular head (no shaft overlap).
/// Used by both on-screen paint and full-res composite.
private func drawArrow(from: NSPoint, to: NSPoint, lineWidth: CGFloat, headLength: CGFloat) {
    let angle = atan2(to.y - from.y, to.x - from.x)
    let headAngle: CGFloat = .pi / 6

    let p1 = NSPoint(x: to.x - headLength * cos(angle - headAngle),
                      y: to.y - headLength * sin(angle - headAngle))
    let p2 = NSPoint(x: to.x - headLength * cos(angle + headAngle),
                      y: to.y - headLength * sin(angle + headAngle))

    // Shaft stops at arrowhead base (midpoint of p1–p2)
    let base = NSPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)

    let shaft = NSBezierPath()
    shaft.move(to: from)
    shaft.line(to: base)
    shaft.lineWidth = lineWidth
    shaft.lineCapStyle = .round
    shaft.stroke()

    let head = NSBezierPath()
    head.move(to: to)
    head.line(to: p1)
    head.line(to: p2)
    head.close()
    head.fill()
}

// MARK: – Canvas view

final class DrawingCanvasView: NSView {
    var currentTool: AnnotationTool = .pen
    var strokeColor: NSColor = .systemRed
    var lineWidth: CGFloat = 3

    private var annotations: [Annotation] = []
    private var active: Annotation?
    let image: NSImage

    // For text entry
    private var pendingTextOrigin: NSPoint?
    private var textField: NSTextField?

    init(image: NSImage, frame: NSRect) {
        self.image = image
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        switch currentTool {
        case .text:
            addCursorRect(bounds, cursor: .iBeam)
        default:
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    // MARK: Draw

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds)
        for a in annotations { paint(a) }
        if let a = active { paint(a) }
    }

    private func paint(_ a: Annotation) {
        guard !a.points.isEmpty else { return }
        a.color.setStroke()
        a.color.setFill()

        switch a.tool {
        case .pen:   paintPen(a)
        case .line:  paintLine(a)
        case .arrow: paintArrow(a)
        case .rect:  paintRect(a)
        case .oval:  paintOval(a)
        case .text:  paintText(a)
        }
    }

    private func paintPen(_ a: Annotation) {
        if a.points.count == 1 {
            let r = NSRect(x: a.points[0].x - a.lineWidth/2, y: a.points[0].y - a.lineWidth/2,
                           width: a.lineWidth, height: a.lineWidth)
            NSBezierPath(ovalIn: r).fill()
            return
        }
        let path = NSBezierPath()
        path.move(to: a.points[0])
        a.points.dropFirst().forEach { path.line(to: $0) }
        path.lineWidth = a.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func paintLine(_ a: Annotation) {
        guard a.points.count >= 2 else { return }
        let path = NSBezierPath()
        path.move(to: a.points[0])
        path.line(to: a.points[1])
        path.lineWidth = a.lineWidth
        path.lineCapStyle = .round
        path.stroke()
    }

    private func paintArrow(_ a: Annotation) {
        guard a.points.count >= 2 else { return }
        drawArrow(from: a.points[0], to: a.points[1],
                  lineWidth: a.lineWidth,
                  headLength: max(a.lineWidth * 4, 14))
    }

    private func paintRect(_ a: Annotation) {
        guard a.points.count >= 2 else { return }
        let r = rectFromTwoPoints(a.points[0], a.points[1])
        let path = NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)
        path.lineWidth = a.lineWidth
        path.stroke()
    }

    private func paintOval(_ a: Annotation) {
        guard a.points.count >= 2 else { return }
        let r = rectFromTwoPoints(a.points[0], a.points[1])
        let path = NSBezierPath(ovalIn: r)
        path.lineWidth = a.lineWidth
        path.stroke()
    }

    private func paintText(_ a: Annotation) {
        guard let text = a.text, !text.isEmpty else { return }
        let fontSize = max(a.lineWidth * 5, 14)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: a.color
        ]
        text.draw(at: a.points[0], withAttributes: attrs)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        if currentTool == .text {
            commitTextField()
            pendingTextOrigin = pt
            showTextField(at: pt)
            return
        }

        active = Annotation(tool: currentTool, color: strokeColor, lineWidth: lineWidth,
                            points: [pt], text: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard active != nil else { return }
        let pt = convert(event.locationInWindow, from: nil)

        switch active!.tool {
        case .pen:
            active!.points.append(pt)
        case .line, .arrow, .rect, .oval:
            if active!.points.count == 1 { active!.points.append(pt) }
            else { active!.points[1] = pt }
        case .text:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let a = active { annotations.append(a) }
        active = nil
        needsDisplay = true
    }

    // MARK: Text field

    private func showTextField(at pt: NSPoint) {
        let fontSize = max(lineWidth * 5, 14)
        let fieldH = fontSize + 12
        let fieldW = max(bounds.width - pt.x - 8, 120)

        let field = NSTextField(frame: NSRect(x: pt.x, y: pt.y - 2, width: fieldW, height: fieldH))
        field.font = .systemFont(ofSize: fontSize, weight: .medium)
        field.textColor = strokeColor
        field.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        field.isBordered = false
        field.isBezeled = false
        field.focusRingType = .none
        field.drawsBackground = true
        field.isEditable = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.target = self
        field.action = #selector(textFieldCommitted)
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
    }

    @objc private func textFieldCommitted() {
        commitTextField()
    }

    private func commitTextField() {
        guard let field = textField, let origin = pendingTextOrigin else { return }
        let text = field.stringValue
        field.removeFromSuperview()
        textField = nil
        guard !text.isEmpty else { pendingTextOrigin = nil; return }

        let annotation = Annotation(tool: .text, color: strokeColor, lineWidth: lineWidth,
                                    points: [origin], text: text)
        annotations.append(annotation)
        pendingTextOrigin = nil
        needsDisplay = true
    }

    // MARK: Actions

    func undo() {
        commitTextField()
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        needsDisplay = true
    }

    /// Returns the image + annotations composited at the original *pixel*
    /// resolution. `lockFocus` would re-rasterize at 1× and throw away the
    /// Retina pixels, so we render into an explicit bitmap rep instead.
    func compositeImage() -> NSImage {
        commitTextField()

        let srcRep = image.representations.compactMap { $0 as? NSBitmapImageRep }.first
        let pxW = srcRep?.pixelsWide ?? max(Int(image.size.width), 1)
        let pxH = srcRep?.pixelsHigh ?? max(Int(image.size.height), 1)

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pxW, pixelsHigh: pxH,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            return image
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        // Draw in pixel coordinates: the source fills the whole bitmap and
        // the annotations scale from canvas points to pixels.
        image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(pxW), height: CGFloat(pxH)))
        let sx = CGFloat(pxW) / bounds.width
        let sy = CGFloat(pxH) / bounds.height
        for a in annotations {
            compositeAnnotation(a, sx: sx, sy: sy)
        }
        ctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        rep.size = image.size                 // point size → correct DPI metadata
        let out = NSImage(size: image.size)
        out.addRepresentation(rep)
        return out
    }

    private func compositeAnnotation(_ a: Annotation, sx: CGFloat, sy: CGFloat) {
        let scaledPts = a.points.map { NSPoint(x: $0.x * sx, y: $0.y * sy) }
        let lw = a.lineWidth * sx
        a.color.setStroke()
        a.color.setFill()

        switch a.tool {
        case .pen:
            if scaledPts.count == 1 {
                let r = NSRect(x: scaledPts[0].x - lw/2, y: scaledPts[0].y - lw/2,
                               width: lw, height: lw)
                NSBezierPath(ovalIn: r).fill()
                return
            }
            let path = NSBezierPath()
            path.move(to: scaledPts[0])
            scaledPts.dropFirst().forEach { path.line(to: $0) }
            path.lineWidth = lw
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()

        case .line:
            guard scaledPts.count >= 2 else { return }
            let path = NSBezierPath()
            path.move(to: scaledPts[0])
            path.line(to: scaledPts[1])
            path.lineWidth = lw
            path.lineCapStyle = .round
            path.stroke()

        case .arrow:
            guard scaledPts.count >= 2 else { return }
            drawArrow(from: scaledPts[0], to: scaledPts[1],
                      lineWidth: lw,
                      headLength: max(lw * 4, 14 * sx))

        case .rect:
            guard scaledPts.count >= 2 else { return }
            let r = rectFromTwoPoints(scaledPts[0], scaledPts[1])
            let path = NSBezierPath(roundedRect: r, xRadius: 2 * sx, yRadius: 2 * sy)
            path.lineWidth = lw
            path.stroke()

        case .oval:
            guard scaledPts.count >= 2 else { return }
            let r = rectFromTwoPoints(scaledPts[0], scaledPts[1])
            let path = NSBezierPath(ovalIn: r)
            path.lineWidth = lw
            path.stroke()

        case .text:
            guard let text = a.text, !text.isEmpty else { return }
            let fontSize = max(a.lineWidth * 5, 14) * sx
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: a.color
            ]
            text.draw(at: scaledPts[0], withAttributes: attrs)
        }
    }

    // MARK: Helpers

    private func rectFromTwoPoints(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}

// MARK: – Tool button

private final class ToolButton: NSView {
    let tool: AnnotationTool
    var isSelected = false { didSet { updateAppearance() } }
    var onTap: (() -> Void)?
    private let iconView: NSImageView

    init(tool: AnnotationTool) {
        self.tool = tool
        iconView = NSImageView(frame: NSRect(x: 6, y: 6, width: 22, height: 22))
        super.init(frame: NSRect(x: 0, y: 0, width: 34, height: 34))
        wantsLayer = true
        layer?.cornerRadius = 6
        toolTip = tool.label

        if let img = NSImage(systemSymbolName: tool.icon,
                             accessibilityDescription: tool.label)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) {
            iconView.image = img
            iconView.imageScaling = .scaleProportionallyDown
        }
        iconView.contentTintColor = .white.withAlphaComponent(0.7)
        addSubview(iconView)
        updateAppearance()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func updateAppearance() {
        layer?.backgroundColor = isSelected
            ? NSColor.white.withAlphaComponent(0.18).cgColor
            : CGColor.clear
        iconView.contentTintColor = isSelected
            ? .white
            : .white.withAlphaComponent(0.7)
    }

    override func mouseDown(with event: NSEvent) { onTap?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }
    override func mouseEntered(with event: NSEvent) {
        if !isSelected { layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor }
    }
    override func mouseExited(with event: NSEvent) {
        if !isSelected { layer?.backgroundColor = .clear }
    }
}

// MARK: – Color dot

private final class ColorDot: NSView {
    let color: NSColor
    var isSelected = false { didSet { needsDisplay = true } }
    var onTap: (() -> Void)?

    init(_ color: NSColor) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = isSelected ? 3 : 1
        let fill = NSBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset))
        color.setFill()
        fill.fill()
        if isSelected {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = 1.5
            NSColor.white.setStroke()
            ring.stroke()
        }
    }
    override func mouseDown(with event: NSEvent) { onTap?() }
}

// MARK: – Separator

private final class ToolbarSeparator: NSView {
    init(height: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: height))
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: – Annotation window controller

final class AnnotationWindowController: NSWindowController {
    private static var instance: AnnotationWindowController?
    private var canvas: DrawingCanvasView!
    private var toolButtons: [ToolButton] = []
    private var colorDots: [ColorDot] = []
    private var widthSlider: NSSlider!
    private let imageAspect: CGFloat  // width / height
    private let toolbarH: CGFloat = 44

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
        imageAspect = image.size.width / image.size.height

        // Fit within 80% of the screen
        let screen = NSScreen.main!
        let maxW = screen.visibleFrame.width * 0.8
        let maxH = (screen.visibleFrame.height - toolbarH) * 0.8
        let scale = min(maxW / image.size.width, maxH / image.size.height, 2.0)
        let cw = image.size.width * scale
        let ch = image.size.height * scale

        // Toolbar needs ~790pt minimum for all controls + right-aligned buttons
        let minToolbarW: CGFloat = 790
        let winW = max(cw, minToolbarW)
        let winH = ch + toolbarH
        let origin = NSPoint(
            x: screen.visibleFrame.midX - winW / 2,
            y: screen.visibleFrame.midY - winH / 2
        )

        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: NSSize(width: winW, height: winH)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "SnapFloat — Annotate"
        win.isReleasedWhenClosed = false
        win.level = .floating
        // Prevent shrinking below toolbar width
        win.minSize = NSSize(width: minToolbarW, height: toolbarH + 120)

        super.init(window: win)
        win.delegate = self

        guard let content = win.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(white: 0.15, alpha: 1).cgColor

        // ── Toolbar ──
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: winW, height: toolbarH))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(white: 0.11, alpha: 1).cgColor
        bar.autoresizingMask = [.width]
        content.addSubview(bar)
        buildToolbar(in: bar, h: toolbarH)

        // ── Canvas (centered, aspect-fit) ──
        canvas = DrawingCanvasView(image: image, frame: .zero)
        content.addSubview(canvas)
        layoutCanvas()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Canvas layout (aspect-fit)

    private func layoutCanvas() {
        guard let content = window?.contentView else { return }
        let availW = content.bounds.width
        let availH = content.bounds.height - toolbarH

        // Aspect-fit the image into available space
        let fitScale = min(availW / imageAspect, availH)  // fitScale = fitted height
        let canvasH = min(fitScale, availH)
        let canvasW = canvasH * imageAspect

        let x = (availW - canvasW) / 2
        let y = toolbarH + (availH - canvasH) / 2

        canvas.frame = NSRect(x: x, y: y, width: canvasW, height: canvasH)
        canvas.needsDisplay = true
    }

    // MARK: Toolbar

    private func buildToolbar(in bar: NSView, h: CGFloat) {
        var x: CGFloat = 10

        // ── Tool picker ──
        for (i, tool) in AnnotationTool.allCases.enumerated() {
            let btn = ToolButton(tool: tool)
            btn.frame.origin = NSPoint(x: x, y: (h - 34) / 2)
            btn.onTap = { [weak self] in self?.selectTool(i) }
            bar.addSubview(btn)
            toolButtons.append(btn)
            x += 38
        }
        toolButtons.first?.isSelected = true
        x += 6

        // ── Separator ──
        let sep1 = ToolbarSeparator(height: h - 16)
        sep1.frame.origin = NSPoint(x: x, y: 8)
        bar.addSubview(sep1)
        x += 10

        // ── Width slider ──
        widthSlider = NSSlider(frame: NSRect(x: x, y: (h - 18) / 2, width: 80, height: 18))
        widthSlider.minValue = 1
        widthSlider.maxValue = 12
        widthSlider.doubleValue = 3
        widthSlider.target = self
        widthSlider.action = #selector(widthChanged)
        widthSlider.isContinuous = true
        bar.addSubview(widthSlider)
        x += 88

        // ── Separator ──
        let sep2 = ToolbarSeparator(height: h - 16)
        sep2.frame.origin = NSPoint(x: x, y: 8)
        bar.addSubview(sep2)
        x += 10

        // ── Color palette ──
        let palette: [NSColor] = [
            .systemRed, .systemOrange, .systemYellow,
            .systemGreen, .systemBlue, .white, .black
        ]
        for (i, color) in palette.enumerated() {
            let dot = ColorDot(color)
            dot.frame.origin = NSPoint(x: x, y: (h - 22) / 2)
            dot.onTap = { [weak self] in self?.selectColor(i) }
            bar.addSubview(dot)
            colorDots.append(dot)
            x += 27
        }
        colorDots.first?.isSelected = true

        // ── Action buttons (right-aligned) ──
        let actions: [(String, String, Selector)] = [
            ("Undo", "arrow.uturn.backward", #selector(didUndo)),
            ("Copy", "doc.on.doc",           #selector(didCopy)),
            ("Save", "square.and.arrow.down", #selector(didSave)),
        ]

        let btnW: CGFloat = 70
        let btnGap: CGFloat = 6
        let totalBtns = btnW * CGFloat(actions.count) + btnGap * CGFloat(actions.count - 1)

        let btnContainer = NSView(frame: NSRect(x: bar.frame.width - totalBtns - 10,
                                                 y: 0, width: totalBtns, height: h))
        btnContainer.autoresizingMask = [.minXMargin]
        bar.addSubview(btnContainer)

        var bx: CGFloat = 0
        for (title, icon, sel) in actions {
            let btn = makeActionButton(title: title, icon: icon, width: btnW)
            btn.frame.origin = NSPoint(x: bx, y: (h - 24) / 2)
            btn.target = self
            btn.action = sel
            btnContainer.addSubview(btn)
            bx += btnW + btnGap
        }
    }

    private func makeActionButton(title: String, icon: String, width: CGFloat) -> NSButton {
        let b = NSButton(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .medium)) {
            b.image = img
            b.imagePosition = .imageLeading
        }
        b.title = title
        b.bezelStyle = .rounded
        b.font = .systemFont(ofSize: 11, weight: .medium)
        return b
    }

    // MARK: Selections

    private func selectTool(_ index: Int) {
        toolButtons.forEach { $0.isSelected = false }
        toolButtons[index].isSelected = true
        canvas.currentTool = AnnotationTool.allCases[index]
        canvas.window?.invalidateCursorRects(for: canvas)
    }

    private func selectColor(_ index: Int) {
        colorDots.forEach { $0.isSelected = false }
        colorDots[index].isSelected = true
        canvas.strokeColor = colorDots[index].color
    }

    @objc private func widthChanged() {
        canvas.lineWidth = CGFloat(widthSlider.doubleValue)
    }

    // MARK: Actions

    @objc private func didUndo() { canvas.undo() }

    @objc private func didCopy() {
        SettingsManager.copyToClipboard(canvas.compositeImage())
        window?.close()
    }

    @objc private func didSave() {
        let img = canvas.compositeImage()
        if SettingsManager.shared.saveDirectoryURL == nil {
            SettingsWindowController.show()
            return
        }
        SettingsManager.saveToDiskIfNeeded(img)
        window?.close()
    }
}

extension AnnotationWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        AnnotationWindowController.instance = nil
    }

    func windowDidResize(_ notification: Notification) {
        layoutCanvas()
    }
}
