import AppKit

/// Centralised access to user preferences via UserDefaults.
final class SettingsManager {

    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    // MARK: – Keys

    private enum Key: String {
        case previewDuration   = "previewDuration"
        case saveLocation      = "saveLocation"
        case autoSaveEnabled   = "autoSaveEnabled"
    }

    // MARK: – Preview duration (seconds)

    /// How long the thumbnail stays visible before auto-copy+dismiss.
    var previewDuration: TimeInterval {
        get {
            let val = defaults.double(forKey: Key.previewDuration.rawValue)
            return val > 0 ? val : 5.0
        }
        set { defaults.set(newValue, forKey: Key.previewDuration.rawValue) }
    }

    // MARK: – Auto-save to disk

    var autoSaveEnabled: Bool {
        get { defaults.bool(forKey: Key.autoSaveEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.autoSaveEnabled.rawValue) }
    }

    /// Folder path where screenshots are saved. `nil` → don't save to disk.
    var saveLocation: String? {
        get { defaults.string(forKey: Key.saveLocation.rawValue) }
        set { defaults.set(newValue, forKey: Key.saveLocation.rawValue) }
    }

    /// Resolved URL, creating the directory if needed. Returns `nil` when
    /// auto-save is off or the path is unset.
    var saveDirectoryURL: URL? {
        guard autoSaveEnabled, let path = saveLocation, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: – Save helper

    /// Writes `image` as PNG into the configured save directory (if any).
    @discardableResult
    static func saveToDiskIfNeeded(_ image: NSImage) -> URL? {
        guard let dir = shared.saveDirectoryURL else { return nil }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "SnapFloat_\(formatter.string(from: Date())).png"
        let fileURL = dir.appendingPathComponent(name)
        try? png.write(to: fileURL)
        return fileURL
    }

    private init() {}
}
