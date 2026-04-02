import AppKit
import ServiceManagement
import UserNotifications

/// Centralised access to user preferences via UserDefaults.
final class SettingsManager {

    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    // MARK: – Keys

    private enum Key: String {
        case previewDuration = "previewDuration"
        case saveLocation    = "saveLocation"
        case autoSaveEnabled = "autoSaveEnabled"
        case captureAction   = "captureAction"
    }

    // MARK: – Capture action (what happens right after a screenshot is taken)

    enum CaptureAction: Int {
        case copyToClipboard       = 0
        case doNothing             = 1
        case saveToFolder          = 2
        case copyAndSaveToFolder   = 3
    }

    var captureAction: CaptureAction {
        get {
            let raw = defaults.integer(forKey: Key.captureAction.rawValue)
            return CaptureAction(rawValue: raw) ?? .copyToClipboard
        }
        set { defaults.set(newValue.rawValue, forKey: Key.captureAction.rawValue) }
    }

    // MARK: – Preview duration (seconds)

    var previewDuration: TimeInterval {
        get {
            let val = defaults.double(forKey: Key.previewDuration.rawValue)
            return val > 0 ? val : 5.0
        }
        set { defaults.set(newValue, forKey: Key.previewDuration.rawValue) }
    }

    // MARK: – Save to disk

    var autoSaveEnabled: Bool {
        get { defaults.bool(forKey: Key.autoSaveEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.autoSaveEnabled.rawValue) }
    }

    var saveLocation: String? {
        get { defaults.string(forKey: Key.saveLocation.rawValue) }
        set { defaults.set(newValue, forKey: Key.saveLocation.rawValue) }
    }

    /// Resolved URL, creating the directory if needed.
    var saveDirectoryURL: URL? {
        guard autoSaveEnabled, let path = saveLocation, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: – Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            if newValue {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }

    // MARK: – Notifications

    static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let showAction = UNNotificationAction(identifier: "SHOW_IN_FINDER",
                                              title: "Show in Finder",
                                              options: .foreground)
        let category = UNNotificationCategory(identifier: "SAVE_COMPLETE",
                                              actions: [showAction],
                                              intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func postSaveNotification(fileURL: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Screenshot saved"
        content.body = fileURL.lastPathComponent
        content.categoryIdentifier = "SAVE_COMPLETE"
        content.userInfo = ["filePath": fileURL.path]
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: – Save helper

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
        postSaveNotification(fileURL: fileURL)
        return fileURL
    }

    // MARK: – Perform capture action

    /// Execute the configured action immediately after a screenshot is taken.
    static func performCaptureAction(image: NSImage) {
        switch shared.captureAction {
        case .copyToClipboard:
            copyToClipboard(image)
        case .doNothing:
            break
        case .saveToFolder:
            saveToDiskIfNeeded(image)
        case .copyAndSaveToFolder:
            copyToClipboard(image)
            saveToDiskIfNeeded(image)
        }
    }

    private static func copyToClipboard(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    private init() {}
}
