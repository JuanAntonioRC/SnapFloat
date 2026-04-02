import AppKit
import CoreGraphics

/// Captures a region of the screen and hands the image to ThumbnailWindowController.
/// `screenRect` must be in AppKit screen coordinates (origin bottom-left of primary display).
final class ScreenCaptureManager {

    static func capture(rect screenRect: NSRect) {
        guard let image = captureImage(rect: screenRect) else {
            NSLog("SnapFloat: capture failed – Screen Recording permission granted?")
            return
        }
        ThumbnailWindowController.show(image: image, originalSize: screenRect.size)
    }

    // MARK: – Private

    private static func captureImage(rect screenRect: NSRect) -> NSImage? {
        // 1. Find which screen contains the selection.
        let centre = NSPoint(x: screenRect.midX, y: screenRect.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(centre) } ?? NSScreen.screens.first!

        guard let nsNum = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        let displayID = CGDirectDisplayID(nsNum.uint32Value)

        // 2. Build the CG rect using CGDisplayBounds.
        //
        //    WHY: CGWindowListCreateImage needs global CG coordinates
        //    (origin = top-left of primary display, Y increases downward).
        //
        //    The naive formula   cgY = NSScreen.main!.frame.height - appkitY - h
        //    is WRONG on secondary displays because NSScreen.main returns the
        //    screen with keyboard focus, NOT necessarily the primary display.
        //    Using CGDisplayBounds avoids any dependency on NSScreen.main.
        //
        //    Step A – convert selection to display-local coordinates.
        //    AppKit origin is bottom-left of the display; CG origin is top-left.
        let localX         = screenRect.origin.x - screen.frame.origin.x
        let localFromBottom = screenRect.origin.y - screen.frame.origin.y
        let localCGY       = screen.frame.height - localFromBottom - screenRect.height

        //    Step B – offset by the display's own position in global CG space.
        let displayBounds = CGDisplayBounds(displayID)   // top-left origin, Y down, points
        let cgRect = CGRect(
            x: displayBounds.origin.x + localX,
            y: displayBounds.origin.y + localCGY,
            width:  screenRect.width,
            height: screenRect.height
        )

        // 3. CGWindowListCreateImage composites every on-screen window via the
        //    WindowServer, so windows floating above the desktop are included.
        //    (CGDisplayCreateImage only reads the raw framebuffer – no windows.)
        guard let cgImage = CGWindowListCreateImage(
            cgRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) else { return nil }

        return NSImage(cgImage: cgImage, size: screenRect.size)
    }
}
