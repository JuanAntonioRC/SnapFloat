import AppKit

/// Floating thumbnail shown after a capture.
/// - Click image → opens the annotation editor.
/// - Save button → saves original to disk (requires configured save folder).
/// - No click → copies original image to clipboard and dismisses after configured duration.
final class ThumbnailWindowController: NSWindowController {

    private static var instance: ThumbnailWindowController?

    private var dismissTimer: Timer?
    private let capturedImage: NSImage
    private var saveButton: NSButton!

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
                        1.0) // never upscale tiny selections
        let thumbSize = NSSize(width: max(originalSize.width * scale, 40),
                               height: max(originalSize.height * scale, 40))

        let stripH: CGFloat = 28
        let panelSize = NSSize(width: thumbSize.width, height: thumbSize.height + stripH)

        // Place in the bottom-right of the screen's visible frame
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

        // ── Outer clickable container (handles click on image → open editor) ──
        let clickView = ClickableView(frame: NSRect(origin: .zero, size: panelSize))
        clickView.onClick = { [weak self] in self?.openEditor() }
        clickView.wantsLayer = true
        clickView.layer?.cornerRadius = 8
        clickView.layer?.masksToBounds = true
        clickView.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        clickView.layer?.borderWidth = 1

        // Image view — sits above the strip
        let imageView = NSImageView(frame: NSRect(x: 0, y: stripH, width: thumbSize.width, height: thumbSize.height))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        clickView.addSubview(imageView)

        // ── Bottom strip — blocks click propagation to clickView ──
        let strip = EventBlockingView(frame: NSRect(x: 0, y: 0, width: panelSize.width, height: stripH))
        strip.wantsLayer = true
        strip.layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
        clickView.addSubview(strip)

        // Save button inside the strip
        let btn = NSButton(frame: strip.bounds)
        btn.title = "Guardar"
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.font = .systemFont(ofSize: 11, weight: .medium)
        btn.contentTintColor = .white
        btn.target = self
        btn.action = #selector(saveTapped)
        if let img = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil) {
            btn.image = img
            btn.imagePosition = .imageLeading
        }
        strip.addSubview(btn)
        saveButton = btn

        panel.contentView = clickView

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

    /// Image click → open annotation editor (dismiss thumbnail, timer cancelled).
    private func openEditor() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        window?.orderOut(nil)
        ThumbnailWindowController.instance = nil
        AnnotationWindowController.show(image: capturedImage)
    }

    /// Save button → save original to disk. If no folder configured, open Settings.
    @objc private func saveTapped() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        if SettingsManager.shared.saveDirectoryURL == nil {
            // No save location set — open Settings so the user can configure one
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

private final class ClickableView: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
    }
    override func mouseExited(with event: NSEvent) {
        layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                      options: [.mouseEnteredAndExited, .activeAlways],
                                      owner: self))
    }
}

/// A plain view that swallows mouse events so they don't propagate to ClickableView.
private final class EventBlockingView: NSView {
    override func mouseDown(with event: NSEvent) { /* consume */ }
}
