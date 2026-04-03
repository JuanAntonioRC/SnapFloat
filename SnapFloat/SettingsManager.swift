import AppKit
import ServiceManagement
import UserNotifications

/// Centralised access to user preferences via UserDefaults.
final class SettingsManager {

    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    static let hotkeyDidChangeNotification = Notification.Name("com.snapfloat.hotkeyDidChange")

    // MARK: – Keys

    private enum Key: String {
        case previewDuration = "previewDuration"
        case saveLocation    = "saveLocation"
        case autoSaveEnabled = "autoSaveEnabled"
        case captureAction   = "captureAction"
        case hotkeyKeyCode       = "hotkeyKeyCode"
        case hotkeyModifiers     = "hotkeyModifiers"
        case fullQualityCapture  = "fullQualityCapture"
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

    // MARK: – Capture quality

    /// When enabled, captures at full Retina resolution (2× pixels on Retina displays)
    /// and preserves uncompressed pixel data for clipboard/save.
    /// When disabled, captures at standard 1× resolution for smaller file sizes.
    var fullQualityCapture: Bool {
        get {
            guard defaults.object(forKey: Key.fullQualityCapture.rawValue) != nil else { return true }
            return defaults.bool(forKey: Key.fullQualityCapture.rawValue)
        }
        set { defaults.set(newValue, forKey: Key.fullQualityCapture.rawValue) }
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

    // MARK: – Hotkey (default: ⇧⌘2)

    var hotkeyKeyCode: UInt32 {
        get {
            guard defaults.object(forKey: Key.hotkeyKeyCode.rawValue) != nil else { return 0x13 }
            return UInt32(defaults.integer(forKey: Key.hotkeyKeyCode.rawValue))
        }
        set { defaults.set(Int(newValue), forKey: Key.hotkeyKeyCode.rawValue) }
    }

    var hotkeyModifiers: UInt32 {
        get {
            guard defaults.object(forKey: Key.hotkeyModifiers.rawValue) != nil else { return 0x300 }
            return UInt32(defaults.integer(forKey: Key.hotkeyModifiers.rawValue))
        }
        set { defaults.set(Int(newValue), forKey: Key.hotkeyModifiers.rawValue) }
    }

    func setHotkey(keyCode: UInt32, modifiers: UInt32) {
        hotkeyKeyCode = keyCode
        hotkeyModifiers = modifiers
        NotificationCenter.default.post(name: Self.hotkeyDidChangeNotification, object: nil)
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
        let rep: NSBitmapImageRep?
        if shared.fullQualityCapture {
            // Use the bitmap rep directly (preserves full Retina pixels)
            // instead of going through tiffRepresentation which can downsample.
            rep = image.representations
                .compactMap({ $0 as? NSBitmapImageRep }).first
                ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    .map({ NSBitmapImageRep(cgImage: $0) })
        } else {
            if let tiff = image.tiffRepresentation {
                rep = NSBitmapImageRep(data: tiff)
            } else {
                rep = nil
            }
        }
        guard let rep, let png = rep.representation(using: .png, properties: [:])
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
        if shared.fullQualityCapture,
           let rep = image.representations
                .compactMap({ $0 as? NSBitmapImageRep }).first
                ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    .map({ NSBitmapImageRep(cgImage: $0) }) {
            // Full-res PNG + uncompressed TIFF so every app gets the best it supports.
            if let png = rep.representation(using: .png, properties: [:]) {
                pb.setData(png, forType: .png)
            }
            if let tiff = rep.representation(using: .tiff, properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.none]) {
                pb.setData(tiff, forType: .tiff)
            }
        } else {
            pb.writeObjects([image])
        }
    }

    private init() {}
}
