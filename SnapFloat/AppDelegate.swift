import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    private var captureMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Trigger the Screen Recording permission dialog once at launch and
        // cache SCDisplay objects. Do NOT call CGRequestScreenCaptureAccess()
        // — it conflicts with ScreenCaptureKit and causes repeated dialogs.
        ScreenCaptureManager.prepareCapture()

        setupMenuBar()

        // Notification permissions + delegate for "Show in Finder"
        SettingsManager.requestNotificationPermission()
        UNUserNotificationCenter.current().delegate = self

        hotkeyManager = HotkeyManager { [weak self] in
            DispatchQueue.main.async { self?.initiateCapture() }
        }
        let sm = SettingsManager.shared
        hotkeyManager?.register(keyCode: sm.hotkeyKeyCode, modifiers: sm.hotkeyModifiers)

        NotificationCenter.default.addObserver(
            self, selector: #selector(hotkeyDidChange),
            name: SettingsManager.hotkeyDidChangeNotification, object: nil
        )
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "SnapFloat")
            button.imageScaling = .scaleProportionallyDown
        }

        let menu = NSMenu()
        let sm = SettingsManager.shared
        let shortcut = HotkeyManager.displayString(forKeyCode: sm.hotkeyKeyCode, modifiers: sm.hotkeyModifiers)
        let captureItem = NSMenuItem(title: "Capture Area  \(shortcut)", action: #selector(initiateCapture), keyEquivalent: "")
        captureItem.target = self
        captureMenuItem = captureItem
        menu.addItem(captureItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SnapFloat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func initiateCapture() {
        CaptureOverlayWindow.show()
    }

    @objc private func openSettings() {
        SettingsWindowController.show()
    }

    @objc private func hotkeyDidChange() {
        let sm = SettingsManager.shared
        hotkeyManager?.register(keyCode: sm.hotkeyKeyCode, modifiers: sm.hotkeyModifiers)
        let shortcut = HotkeyManager.displayString(forKeyCode: sm.hotkeyKeyCode, modifiers: sm.hotkeyModifiers)
        captureMenuItem?.title = "Capture Area  \(shortcut)"
    }
}

// MARK: – Notification delegate (handle "Show in Finder")

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Handle "Mostrar en Finder" action
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "SHOW_IN_FINDER",
           let path = response.notification.request.content.userInfo["filePath"] as? String {
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        completionHandler()
    }
}
