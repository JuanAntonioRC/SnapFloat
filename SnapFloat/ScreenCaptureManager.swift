import AppKit
import CoreGraphics

/// Captures a region of the screen and hands the image to ThumbnailWindowController.
/// `screenRect` must be in AppKit screen coordinates (origin bottom-left of primary display).
final class ScreenCaptureManager {

    static func capture(rect screenRect: NSRect) {
        let image = captureImage(rect: screenRect)
        guard let image else {
            NSLog("SnapFloat: CGWindowListCreateImage returned nil – Screen Recording permission granted?")
            return
        }
        ThumbnailWindowController.show(image: image, originalSize: screenRect.size)
    }

    // MARK: – Private

    private static func captureImage(rect screenRect: NSRect) -> NSImage? {
        // Convert AppKit coords (origin bottom-left) → CG coords (origin top-left of main display)
        let mainH = NSScreen.main!.frame.height
        let cgRect = CGRect(
            x: screenRect.origin.x,
            y: mainH - screenRect.origin.y - screenRect.height,
            width: screenRect.width,
            height: screenRect.height
        )

        // CGWindowListCreateImage is deprecated in macOS 14, but still functional.
        // Migration to ScreenCaptureKit is a planned post-MVP step.
        let cgImage = CGWindowListCreateImage(
            cgRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        )
        guard let cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: screenRect.size)
    }
}
