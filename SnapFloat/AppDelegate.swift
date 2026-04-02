import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Trigger the Screen Recording permission dialog once at launch and
        // cache SCDisplay objects. Do NOT call CGRequestScreenCaptureAccess()
        // — it conflicts with ScreenCaptureKit and causes repeated dialogs.
        ScreenCaptureManager.prepareCapture()

        setupMenuBar()

        hotkeyManager = HotkeyManager { [weak self] in
            DispatchQueue.main.async { self?.initiateCapture() }
        }
        hotkeyManager?.register()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "SnapFloat")
            button.imageScaling = .scaleProportionallyDown
        }

        let menu = NSMenu()
        let captureItem = NSMenuItem(title: "Capturar área  ⇧⌘2", action: #selector(initiateCapture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de SnapFloat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func initiateCapture() {
        CaptureOverlayWindow.show()
    }
}
