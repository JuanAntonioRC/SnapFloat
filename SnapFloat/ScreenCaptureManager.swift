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

    private static var didPromptPermission = false

    /// Call once at app launch.
    /// If not yet authorized, requests permission once (never touch
    /// SCShareableContent/SCScreenshotManager while unauthorized — each such call
    /// throws its own system prompt). Otherwise caches all connected displays.
    static func prepareCapture() {
        guard CGPreflightScreenCaptureAccess() else { requestPermissionOnce(); return }
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

    /// Full-screen snapshot taken the moment the hotkey fires, before the overlay
    /// takes focus. Taking focus closes the frontmost app's open menus, so we
    /// select on this frozen image (same trick as CleanShot/Shottr) to keep them.
    @MainActor
    static func snapshot(of screen: NSScreen) async -> NSImage? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        return try? await doCapture(rect: screen.frame, screen: screen)
    }

    /// `frozen` is the `snapshot(of:)` of the screen containing `screenRect`;
    /// when present we crop it instead of grabbing live pixels.
    static func capture(rect screenRect: NSRect, frozen: NSImage? = nil) {
        // Preflight check never shows a dialog. Only call ScreenCaptureKit when
        // truly authorized, so a granted app never re-prompts per capture.
        guard CGPreflightScreenCaptureAccess() else { requestPermissionOnce(); return }

        let centre = NSPoint(x: screenRect.midX, y: screenRect.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(centre) } ?? NSScreen.screens.first!

        Task { @MainActor in
            do {
                let img = if let frozen { try crop(frozen, to: screenRect, screen: screen) }
                          else { try await doCapture(rect: screenRect, screen: screen) }
                SettingsManager.performCaptureAction(image: img)
                ThumbnailWindowController.show(image: img, originalSize: screenRect.size, on: screen)
            } catch {
                NSLog("SnapFloat: capture failed – \(error)")
            }
        }
    }

    // MARK: – Private

    /// Adds the app to the Screen Recording list and shows the system prompt +
    /// one guidance alert, at most once per launch. A grant made while running
    /// only takes effect after relaunch, so we point the user there instead of
    /// re-prompting on every capture.
    private static func requestPermissionOnce() {
        guard !didPromptPermission else { return }
        didPromptPermission = true
        CGRequestScreenCaptureAccess()
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Screen Recording permission needed"
            alert.informativeText = "Enable SnapFloat under System Settings › Privacy & Security › Screen Recording, then quit and reopen SnapFloat."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
        }
    }

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

        // Always capture at the display's native pixel density (2× on Retina).
        let scaleFactor = screen.backingScaleFactor

        let config = SCStreamConfiguration()
        config.sourceRect  = CGRect(x: localX, y: localY, width: rect.width, height: rect.height)
        config.width       = max(1, Int(rect.width  * scaleFactor))
        config.height      = max(1, Int(rect.height * scaleFactor))
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        if #available(macOS 14.2, *) {
            config.captureResolution = .best
        }

        let cgImage: CGImage
        if #available(macOS 14.0, *) {
            cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
        } else {
            cgImage = try await StreamCaptureHelper().capture(filter: filter, config: config)
        }

        return makeImage(cgImage, size: rect.size)
    }

    private static func crop(_ frozen: NSImage, to rect: NSRect, screen: NSScreen) throws -> NSImage {
        guard let cg = frozen.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { throw CaptureError.frameFailed }
        // Snapshot pixels are top-left origin; scale points → pixels.
        let scale = CGFloat(cg.width) / screen.frame.width
        let local = CGRect(x: rect.origin.x - screen.frame.origin.x,
                           y: screen.frame.maxY - rect.maxY,
                           width: rect.width, height: rect.height)
        let px = CGRect(x: local.minX * scale, y: local.minY * scale,
                        width: local.width * scale, height: local.height * scale).integral
        guard let cropped = cg.cropping(to: px) else { throw CaptureError.frameFailed }
        return makeImage(cropped, size: rect.size)
    }

    /// NSImage with a bitmap rep that preserves every Retina pixel.
    private static func makeImage(_ cgImage: CGImage, size: NSSize) -> NSImage {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = size                       // point size for display
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
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
        let ctx = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      .highQualityDownsample: true])
        guard let cg = ctx.createCGImage(ci, from: ci.extent,
                                         format: .RGBA8,
                                         colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else {
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
