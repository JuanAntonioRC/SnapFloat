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
        // 1. Find which physical display contains the selection centre.
        let centre = NSPoint(x: screenRect.midX, y: screenRect.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(centre) } ?? NSScreen.main!

        // 2. Get the CGDirectDisplayID for that screen.
        guard let nsNum = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        let displayID = CGDirectDisplayID(nsNum.uint32Value)

        // 3. Capture the full display at native resolution.
        //    CGDisplayCreateImage works per-display, so multi-monitor is unambiguous.
        guard let fullImage = CGDisplayCreateImage(displayID) else { return nil }

        // 4. Convert selection from global AppKit coords → display-local pixel coords.
        //
        //    AppKit global:        origin bottom-left of primary, Y up.
        //    CGDisplayCreateImage: origin top-left of THIS display, Y down.
        //
        //    Step A – make coords relative to this screen's bottom-left corner.
        let scale = screen.backingScaleFactor
        let localX         = screenRect.origin.x - screen.frame.origin.x
        let localFromBottom = screenRect.origin.y - screen.frame.origin.y

        //    Step B – flip Y to top-left origin and multiply to pixels.
        let imgH = CGFloat(fullImage.height)   // native pixel height of this display
        let pixX = localX           * scale
        let pixY = imgH - (localFromBottom + screenRect.height) * scale

        let cropRect = CGRect(
            x: pixX,
            y: pixY,
            width:  screenRect.width  * scale,
            height: screenRect.height * scale
        )

        guard let cropped = fullImage.cropping(to: cropRect) else { return nil }
        // Return the image at logical (point) size so NSImageView scales correctly.
        return NSImage(cgImage: cropped, size: screenRect.size)
    }
}
