import Foundation

/// Centralised access to user preferences via UserDefaults, for the MVP
/// Linux settings surface (no hotkey keys yet — see plan's deferred list).
/// Key names intentionally match SnapFloat/SettingsManager.swift on macOS
/// for consistency, even though the two run against separate UserDefaults
/// stores on separate machines.
public final class AppSettingsStore {

    public static let shared = AppSettingsStore()

    private let defaults = UserDefaults.standard

    private enum Key: String {
        case previewDuration   = "previewDuration"
        case saveLocation      = "saveLocation"
        case autoSaveEnabled   = "autoSaveEnabled"
        case captureAction     = "captureAction"
    }

    public var captureAction: CaptureAction {
        get {
            let raw = defaults.integer(forKey: Key.captureAction.rawValue)
            return CaptureAction(rawValue: raw) ?? .copyToClipboard
        }
        set { defaults.set(newValue.rawValue, forKey: Key.captureAction.rawValue) }
    }

    public var previewDuration: TimeInterval {
        get {
            let val = defaults.double(forKey: Key.previewDuration.rawValue)
            return val > 0 ? val : 5.0
        }
        set { defaults.set(newValue, forKey: Key.previewDuration.rawValue) }
    }

    public var autoSaveEnabled: Bool {
        get { defaults.bool(forKey: Key.autoSaveEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.autoSaveEnabled.rawValue) }
    }

    public var saveLocation: String? {
        get { defaults.string(forKey: Key.saveLocation.rawValue) }
        set { defaults.set(newValue, forKey: Key.saveLocation.rawValue) }
    }

    /// Resolved directory path, creating it if needed. nil when saving is disabled
    /// or no folder has been chosen yet.
    public var saveDirectoryPath: String? {
        guard autoSaveEnabled, let path = saveLocation, !path.isEmpty else { return nil }
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private init() {}
}
