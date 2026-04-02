import AppKit
import ScreenCaptureKit

// MARK: – Errors

private enum CaptureError: Error {
    case displayNotFound, noContent, frameFailed
}

// MARK: – Manager

/// Captures a region of the screen using ScreenCaptureKit (macOS 13+).
/// SCKit routes through the WindowServer compositor, so all on-screen windows
/// are included — unlike CGDisplayCreateImage (raw framebuffer, no windows)
/// or CGWindowListCreateImage (deprecated + broken in macOS 14+).
final class ScreenCaptureManager {

    static func capture(rect screenRect: NSRect) {
        let centre = NSPoint(x: screenRect.midX, y: screenRect.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(centre) } ?? NSScreen.screens.first!

        Task {
            do {
                let img = try await doCapture(rect: screenRect, screen: screen)
                await MainActor.run {
                    ThumbnailWindowController.show(image: img, originalSize: screenRect.size)
                }
            } catch {
                NSLog("SnapFloat: capture failed – \(error)")
            }
        }
    }

    // MARK: Private

    private static func doCapture(rect: NSRect, screen: NSScreen) async throws -> NSImage {
        guard let nsNum = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { throw CaptureError.displayNotFound }
        let displayID = CGDirectDisplayID(nsNum.uint32Value)

        let scDisplay = try await findSCDisplay(id: displayID)

        // Capture every window on this display (no exclusions)
        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])

        // Selection in display-local coordinates: top-left origin, Y down, points.
        let localX = rect.origin.x - screen.frame.origin.x
        let localY = screen.frame.height - (rect.origin.y - screen.frame.origin.y) - rect.height

        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: localX, y: localY, width: rect.width, height: rect.height)
        config.width  = max(1, Int(rect.width  * screen.backingScaleFactor))
        config.height = max(1, Int(rect.height * screen.backingScaleFactor))

        let cgImage: CGImage
        if #available(macOS 14.0, *) {
            // One-shot API introduced in macOS 14 — simple and reliable.
            cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
        } else {
            // macOS 13: capture one frame via SCStream then stop.
            cgImage = try await StreamCaptureHelper().capture(filter: filter, config: config)
        }

        return NSImage(cgImage: cgImage, size: rect.size)
    }

    /// Resolves the SCDisplay that matches a given CGDirectDisplayID.
    private static func findSCDisplay(id displayID: CGDirectDisplayID) async throws -> SCDisplay {
        try await withCheckedThrowingContinuation { cont in
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
                if let error {
                    cont.resume(throwing: error); return
                }
                guard let display = content?.displays.first(where: { $0.displayID == displayID }) else {
                    cont.resume(throwing: CaptureError.displayNotFound); return
                }
                cont.resume(returning: display)
            }
        }
    }
}

// MARK: – SCStream one-shot helper (macOS 13 fallback)

/// Wraps SCStream to produce a single CGImage then stops.
private final class StreamCaptureHelper: NSObject, SCStreamOutput, SCStreamDelegate {
    private var cont: CheckedContinuation<CGImage, Error>?
    private var stream: SCStream?
    private var done = false

    func capture(filter: SCContentFilter, config: SCStreamConfiguration) async throws -> CGImage {
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream!.addStreamOutput(self, type: .screen,
                                    sampleHandlerQueue: .global(qos: .userInitiated))
        return try await withCheckedThrowingContinuation { [weak self] c in
            self?.cont = c
            Task { [weak self] in
                do    { try await self?.stream?.startCapture() }
                catch { self?.finish(.failure(error)) }
            }
        }
    }

    func stream(_ stream: SCStream,
                didOutputSampleBuffer buf: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen else { return }
        Task { try? await stream.stopCapture() }
        guard let pb = buf.imageBuffer else {
            finish(.failure(CaptureError.frameFailed)); return
        }
        let ci = CIImage(cvPixelBuffer: pb)
        guard let cg = CIContext().createCGImage(ci, from: ci.extent) else {
            finish(.failure(CaptureError.frameFailed)); return
        }
        finish(.success(cg))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<CGImage, Error>) {
        guard !done else { return }
        done = true
        switch result {
        case .success(let img): cont?.resume(returning: img)
        case .failure(let err): cont?.resume(throwing: err)
        }
        cont = nil
    }
}
