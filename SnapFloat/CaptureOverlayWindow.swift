import AppKit

/// Full-screen borderless window that sits above everything and hosts the selection view.
final class CaptureOverlayWindow: NSWindow {

    private static var instances: [CaptureOverlayWindow] = []

    // MARK: – Public interface

    static func show() {
        guard instances.isEmpty else { return }

        // Create an overlay on every connected screen
        for screen in NSScreen.screens {
            let win = CaptureOverlayWindow(screen: screen)
            instances.append(win)
            win.orderFront(nil)
        }

        NSCursor.crosshair.push()
        NSApp.activate(ignoringOtherApps: true)

        // Make the window under the cursor key so it receives events
        let mouse = NSEvent.mouseLocation
        let keyWin = instances.first { $0.frame.contains(mouse) } ?? instances.first!
        keyWin.makeKeyAndOrderFront(nil)
        keyWin.makeFirstResponder(keyWin.contentView)
    }

    static func dismiss() {
        NSCursor.pop()
        for win in instances { win.orderOut(nil) }
        instances.removeAll()
    }

    // MARK: – Init

    private init(screen: NSScreen) {
        // NSWindow's designated initializer does NOT include `screen:`.
        // We pass screen.frame (global AppKit coords) so the window lands on the right display.
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let overlayView = CaptureOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        overlayView.screenFrame = screen.frame
        contentView = overlayView
    }

    // Allow any overlay window to become key when clicked
    override var canBecomeKey: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // When user clicks on this overlay, make it key so it receives drag/up events
        makeKeyAndOrderFront(nil)
        makeFirstResponder(contentView)
        super.mouseDown(with: event)
    }
}
