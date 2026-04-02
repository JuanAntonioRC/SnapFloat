import AppKit

/// Full-screen borderless window that sits above everything and hosts the selection view.
final class CaptureOverlayWindow: NSWindow {

    private static var instance: CaptureOverlayWindow?

    // MARK: – Public interface

    static func show() {
        guard instance == nil else { return }

        // Use the screen where the cursor currently is
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!

        let win = CaptureOverlayWindow(screen: screen)
        instance = win
        NSCursor.crosshair.push()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        win.makeFirstResponder(win.contentView)
    }

    static func dismiss() {
        NSCursor.pop()
        instance?.orderOut(nil)
        instance = nil
    }

    // MARK: – Init

    private init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
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

    // Allow Escape to cancel without being key
    override var canBecomeKey: Bool { true }
}
