import AppKit

/// Floating thumbnail shown after a capture.
/// - Click image → opens the annotation editor.
/// - Save button → saves original to disk (requires configured save folder).
/// - No click → copies original image to clipboard and dismisses after configured duration.
final class ThumbnailWindowController: NSWindowController {

    private static var instance: ThumbnailWindowController?

    private var dismissTimer: Timer?
    private let capturedImage: NSImage

    // MARK: – Public

    static func show(image: NSImage, originalSize: NSSize) {
        DispatchQueue.main.async {
            instance?.forceClose()
            let controller = ThumbnailWindowController(image: image, originalSize: originalSize)
            instance = controller
            controller.showWindow(nil)
        }
    }

    // MARK: – Init

    init(image: NSImage, originalSize: NSSize) {
        capturedImage = image

        // Scale thumbnail so longest edge is ≤ 200 pt
        let maxEdge: CGFloat = 200
        let scale = min(maxEdge / max(originalSize.width, 1),
                        maxEdge / max(originalSize.height, 1),
                        1.0)
        let thumbSize = NSSize(width: max(originalSize.width * scale, 40),
                               height: max(originalSize.height * scale, 40))

        let stripH: CGFloat = 32
        let panelWidth = max(thumbSize.width, 100)
        let panelSize = NSSize(width: panelWidth, height: thumbSize.height + stripH)

        let screen = NSScreen.main!
        let margin: CGFloat = 20
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - panelSize.width - margin,
            y: screen.visibleFrame.minY + margin
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init(window: panel)

        // ── Container ──
        let container = NSView(frame: NSRect(origin: .zero, size: panelSize))
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        container.layer?.borderWidth = 1

        // ── Image area (click → open editor) ──
        let clickView = ClickableView(frame: NSRect(x: 0, y: stripH, width: panelWidth, height: thumbSize.height))
        clickView.onClick = { [weak self] in self?.openEditor() }
        let imageView = NSImageView(frame: clickView.bounds)
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        clickView.addSubview(imageView)
        container.addSubview(clickView)

        // ── Bottom strip ──
        let strip = EventBlockingView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: stripH))
        strip.wantsLayer = true
        strip.layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
        container.addSubview(strip)

        // Save button inside strip
        let saveBtn = StripButton(title: "Guardar", systemImage: "square.and.arrow.down")
        saveBtn.frame.origin = NSPoint(x: (panelWidth - saveBtn.frame.width) / 2,
                                       y: (stripH - saveBtn.frame.height) / 2)
        saveBtn.onClick = { [weak self] in self?.saveTapped() }
        strip.addSubview(saveBtn)

        panel.contentView = container

        // Fade in
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }

        // Auto-dismiss after configured duration
        let duration = SettingsManager.shared.previewDuration
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.copyAndDismiss()
        }
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: – Actions

    private func openEditor() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        window?.orderOut(nil)
        ThumbnailWindowController.instance = nil
        AnnotationWindowController.show(image: capturedImage)
    }

    private func saveTapped() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        if SettingsManager.shared.saveDirectoryURL == nil {
            SettingsWindowController.show()
            return
        }

        SettingsManager.saveToDiskIfNeeded(capturedImage)
        animateOut()
    }

    private func copyAndDismiss() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([capturedImage])
        animateOut()
    }

    private func forceClose() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        window?.orderOut(nil)
        ThumbnailWindowController.instance = nil
    }

    private func animateOut() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            window?.animator().alphaValue = 0
        }, completionHandler: {
            self.window?.orderOut(nil)
            ThumbnailWindowController.instance = nil
        })
    }
}

// MARK: – Helper views

/// Clickable area for the image portion.
private final class ClickableView: NSView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// Swallows mouse events so they don't propagate to parent.
private final class EventBlockingView: NSView {
    override func mouseDown(with event: NSEvent) { /* consume */ }
}

/// Reusable strip button with its own rounded hover highlight.
final class StripButton: NSView {
    var onClick: (() -> Void)?

    init(title: String, systemImage: String?) {
        super.init(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        wantsLayer = true
        layer?.cornerRadius = 5

        var xOff: CGFloat = 8

        if let systemImage,
           let img = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .medium)) {
            let iv = NSImageView(frame: NSRect(x: xOff, y: 4, width: 16, height: 16))
            iv.image = img
            iv.contentTintColor = .white
            addSubview(iv)
            xOff += 18
        }

        let lbl = NSTextField(labelWithString: title)
        lbl.font = .systemFont(ofSize: 11, weight: .medium)
        lbl.textColor = .white
        lbl.sizeToFit()
        lbl.frame.origin = NSPoint(x: xOff, y: (24 - lbl.frame.height) / 2)
        addSubview(lbl)

        frame.size.width = xOff + lbl.frame.width + 8
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = .clear
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                      options: [.mouseEnteredAndExited, .activeAlways],
                                      owner: self))
    }
}
