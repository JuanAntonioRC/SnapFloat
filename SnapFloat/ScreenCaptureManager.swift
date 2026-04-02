import AppKit
import ScreenCaptureKit

// MARK: – Errors

private enum CaptureError: Error {
    case displayNotFound, noContent, frameFailed
}

// MARK: – Manager

final class ScreenCaptureManager {

    /// SCDisplay objects cached at launch so we never call SCShareableContent
    /// again per-capture. Repeated SCShareableContent calls are what trigger
    /// the repeated permission dialogs on macOS 14/15.
    private static var displayCache: [CGDirectDisplayID: SCDisplay] = [:]

    // MARK: – Public

    /// Call once at app launch.
    /// Triggers the Screen Recording permission dialog exactly once, then
    /// caches all connected displays for later captures.
    static func prepareCapture() {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            guard let displays = content?.displays else {
                NSLog("SnapFloat: SCShareableContent error at launch – \(String(describing: error))")
                return
            }
            DispatchQueue.main.async {
                for d in displays { self.displayCache[d.displayID] = d }
                NSLog("SnapFloat: cached \(displays.count) display(s)")
            }
        }
    }

    static func capture(rect screenRect: NSRect) {
        let centre = NSPoint(x: screenRect.midX, y: screenRect.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(centre) } ?? NSScreen.screens.first!

        Task { @MainActor in
            do {
                let img = try await doCapture(rect: screenRect, screen: screen)
                ThumbnailWindowController.show(image: img, originalSize: screenRect.size)
            } catch {
                NSLog("SnapFloat: capture failed – \(error)")
            }
        }
    }

    // MARK: – Private

    @MainActor
    private static func doCapture(rect: NSRect, screen: NSScreen) async throws -> NSImage {
        guard let nsNum = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { throw CaptureError.displayNotFound }
        let displayID = CGDirectDisplayID(nsNum.uint32Value)

        // Use cached SCDisplay — no SCShareableContent call, no permission dialog.
        let scDisplay = try await resolveDisplay(id: displayID)

        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])

        // Selection in display-local coords: top-left origin, Y down, points.
        let localX = rect.origin.x - screen.frame.origin.x
        let localY = screen.frame.height - (rect.origin.y - screen.frame.origin.y) - rect.height

        let config = SCStreamConfiguration()
        config.sourceRect  = CGRect(x: localX, y: localY, width: rect.width, height: rect.height)
        config.width       = max(1, Int(rect.width  * screen.backingScaleFactor))
        config.height      = max(1, Int(rect.height * screen.backingScaleFactor))
        config.showsCursor = false

        let cgImage: CGImage
        if #available(macOS 14.0, *) {
            cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
        } else {
            cgImage = try await StreamCaptureHelper().capture(filter: filter, config: config)
        }

        return NSImage(cgImage: cgImage, size: rect.size)
    }

    /// Returns a cached SCDisplay, refreshing the cache once if it's a miss
    /// (e.g. a monitor was connected after launch).
    @MainActor
    private static func resolveDisplay(id: CGDirectDisplayID) async throws -> SCDisplay {
        if let cached = displayCache[id] { return cached }

        // Cache miss – refresh once, then retry.
        await refreshCache()
        guard let display = displayCache[id] else { throw CaptureError.displayNotFound }
        return display
    }

    @MainActor
    private static func refreshCache() async {
        await withCheckedContinuation { cont in
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, _ in
                DispatchQueue.main.async {
                    if let displays = content?.displays {
                        for d in displays { self.displayCache[d.displayID] = d }
                    }
                    cont.resume()
                }
            }
        }
    }
}

// MARK: – SCStream one-shot helper (macOS 13 fallback)

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
        guard let pb = buf.imageBuffer else { finish(.failure(CaptureError.frameFailed)); return }
        let ci = CIImage(cvPixelBuffer: pb)
        guard let cg = CIContext().createCGImage(ci, from: ci.extent) else {
            finish(.failure(CaptureError.frameFailed)); return
        }
        finish(.success(cg))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { finish(.failure(error)) }

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
