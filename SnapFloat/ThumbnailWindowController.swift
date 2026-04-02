import AppKit

/// Floating thumbnail shown after a capture.
/// - Click → opens the annotation editor.
/// - No click → copies original image to clipboard and dismisses after 5 seconds.
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
                        1.0) // never upscale tiny selections
        let thumbSize = NSSize(width: max(originalSize.width * scale, 40),
                               height: max(originalSize.height * scale, 40))

        // Place in the bottom-right of the screen's visible frame
        let screen = NSScreen.main!
        let margin: CGFloat = 20
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - thumbSize.width - margin,
            y: screen.visibleFrame.minY + margin
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: thumbSize),
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

        // Content: image view inside a clickable container
        let clickView = ClickableView(frame: NSRect(origin: .zero, size: thumbSize))
        clickView.onClick = { [weak self] in self?.openEditor() }
        clickView.wantsLayer = true
        clickView.layer?.cornerRadius = 8
        clickView.layer?.masksToBounds = true

        let imageView = NSImageView(frame: clickView.bounds)
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        clickView.addSubview(imageView)

        // Thin white border
        clickView.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        clickView.layer?.borderWidth = 1

        panel.contentView = clickView

        // Fade in
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }

        // Auto-dismiss after 5 s
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.copyAndDismiss()
        }
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: – Actions

    /// Click → open annotation editor (dismiss thumbnail, timer cancelled).
    private func openEditor() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        window?.orderOut(nil)
        ThumbnailWindowController.instance = nil
        AnnotationWindowController.show(image: capturedImage)
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

// MARK: – Helper view

private final class ClickableView: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    // Highlight on hover (optional but nice)
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
