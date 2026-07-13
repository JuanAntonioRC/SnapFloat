import Foundation

/// Centralised access to user preferences via UserDefaults, for the MVP
/// Linux settings surface. Key names intentionally match
/// SnapFloat/SettingsManager.swift on macOS for consistency, even though
/// the two run against separate UserDefaults stores on separate machines.
public final class AppSettingsStore {

    public static let shared = AppSettingsStore()

    private let defaults = UserDefaults.standard

    /// swift-corelibs-foundation's UserDefaults only writes `~/.config/
    /// <processName>.plist` to disk from its own debounced-write timer,
    /// which needs Foundation's RunLoop pumping to ever fire — this app
    /// drives GLib's main loop instead (g_application_run), which never
    /// runs one. Without an explicit synchronize() after every write, every
    /// setting here would silently reset on each relaunch.
    private func set(_ value: Any?, forKey key: Key) {
        defaults.set(value, forKey: key.rawValue)
        defaults.synchronize()
    }

    private enum Key: String {
        case previewDuration    = "previewDuration"
        case saveLocation       = "saveLocation"
        case autoSaveEnabled    = "autoSaveEnabled"
        case captureAction      = "captureAction"
        case useSystemPicker    = "useSystemPicker"
        case shortcutKeyval     = "shortcutKeyval"
        case shortcutModifiers  = "shortcutModifiers"
    }

    /// Linux only: when true, capture uses the desktop's own screenshot
    /// dialog (GNOME's region/window/screen picker) instead of SnapFloat's
    /// instant crop overlay. Default false — the overlay mirrors the macOS
    /// capture-on-release behavior.
    public var useSystemPicker: Bool {
        get { defaults.bool(forKey: Key.useSystemPicker.rawValue) }
        set { set(newValue, forKey: .useSystemPicker) }
    }

    public var captureAction: CaptureAction {
        get {
            let raw = defaults.integer(forKey: Key.captureAction.rawValue)
            return CaptureAction(rawValue: raw) ?? .copyToClipboard
        }
        set { set(newValue.rawValue, forKey: .captureAction) }
    }

    public var previewDuration: TimeInterval {
        get {
            let val = defaults.double(forKey: Key.previewDuration.rawValue)
            return val > 0 ? val : 5.0
        }
        set { set(newValue, forKey: .previewDuration) }
    }

    public var autoSaveEnabled: Bool {
        get { defaults.bool(forKey: Key.autoSaveEnabled.rawValue) }
        set { set(newValue, forKey: .autoSaveEnabled) }
    }

    public var saveLocation: String? {
        get { defaults.string(forKey: Key.saveLocation.rawValue) }
        set { set(newValue, forKey: .saveLocation) }
    }

    /// Resolved directory path, creating it if needed. nil when saving is disabled
    /// or no folder has been chosen yet.
    public var saveDirectoryPath: String? {
        guard autoSaveEnabled, let path = saveLocation, !path.isEmpty else { return nil }
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    /// Linux only: the global-shortcut key combination, registered directly
    /// via X11 (see GlobalHotkey.swift) rather than through a system
    /// keyboard-shortcuts UI. Stored as an X11/GDK KeySym (the two share the
    /// same numeric space for ordinary keys) plus a bitmask of X11 modifiers
    /// (ShiftMask=1, ControlMask=4, Mod1Mask=8 for Alt, Mod4Mask=64 for
    /// Super). Defaults to Ctrl+Shift+2.
    public var shortcutKeyval: UInt32 {
        get {
            let raw = defaults.integer(forKey: Key.shortcutKeyval.rawValue)
            return raw > 0 ? UInt32(raw) : 0x0032 // XK_2 / GDK_KEY_2
        }
        set { set(Int(newValue), forKey: .shortcutKeyval) }
    }

    public var shortcutModifiers: UInt32 {
        get {
            let raw = defaults.integer(forKey: Key.shortcutModifiers.rawValue)
            return raw > 0 ? UInt32(raw) : 5 // ControlMask(4) | ShiftMask(1)
        }
        set { set(Int(newValue), forKey: .shortcutModifiers) }
    }

    private init() {}
}
