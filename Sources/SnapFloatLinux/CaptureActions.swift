import CGtk4Shim
import SnapFloatCore
import Foundation

/// Copy/save primitives shared by the automatic on-capture action
/// (AppController) and the preview's manual Copy/Save buttons
/// (PreviewWindow) and the annotation editor (AnnotationWindow).
/// Mirrors SnapFloat/SettingsManager.swift's performCaptureAction on macOS.
enum CaptureActions {

    static func performConfiguredAction(imagePath: String) {
        switch AppSettingsStore.shared.captureAction {
        case .copyToClipboard:
            copyToClipboard(imagePath: imagePath)
        case .doNothing:
            break
        case .saveToFolder:
            _ = saveToDisk(imagePath: imagePath)
        case .copyAndSaveToFolder:
            copyToClipboard(imagePath: imagePath)
            _ = saveToDisk(imagePath: imagePath)
        }
    }

    static func copyToClipboard(imagePath: String) {
        var error: UnsafeMutablePointer<GError>?
        guard let texture = imagePath.withCString({ gdk_texture_new_from_filename($0, &error) }) else {
            if let error { NSLog("SnapFloat: copy failed – \(String(cString: error.pointee.message))") }
            return
        }
        guard let display = gdk_display_get_default() else { return }
        let clipboard = gdk_display_get_clipboard(display)
        gdk_clipboard_set_texture(clipboard, texture)
    }

    /// Copies `imagePath` into the configured save folder. Returns the
    /// destination path, or nil if no save folder is configured or the
    /// copy failed.
    @discardableResult
    static func saveToDisk(imagePath: String) -> String? {
        guard let dir = AppSettingsStore.shared.saveDirectoryPath else { return nil }
        let destination = (dir as NSString).appendingPathComponent(ScreenshotFileNamer.makeFilename())
        do {
            try FileManager.default.copyItem(atPath: imagePath, toPath: destination)
            LinuxNotifications.postSaveNotification(path: destination)
            return destination
        } catch {
            NSLog("SnapFloat: save failed – \(error)")
            return nil
        }
    }
}
