import CGtk4Shim
import SnapFloatCore
import Foundation

/// Top-level coordinator: owns the shared D-Bus connection, the tray icon,
/// and wires "Capture Area" through to the portal + floating preview.
final class AppController {
    private let app: UnsafeMutablePointer<GtkApplication>
    private var connection: OpaquePointer?
    private var tray: TrayIndicator?
    private var globalShortcut: GlobalShortcut?
    private var grantPromptShownThisRun = false

    init(app: UnsafeMutablePointer<GtkApplication>) {
        self.app = app
    }

    func start() {
        var error: UnsafeMutablePointer<GError>?
        guard let connection = g_bus_get_sync(G_BUS_TYPE_SESSION, nil, &error) else {
            if let error { NSLog("SnapFloat: could not connect to session bus – \(String(cString: error.pointee.message))") }
            return
        }
        self.connection = connection

        let tray = TrayIndicator(
            connection: connection,
            onCapture: { [weak self] in self?.captureArea() },
            onSettings: { [weak self] in self?.openSettings() },
            onQuit: { [weak self] in self?.quit() }
        )
        tray.start()
        self.tray = tray

        let globalShortcut = GlobalShortcut(connection: connection) { [weak self] in self?.captureArea() }
        globalShortcut.onTriggerDescriptionChanged = { [weak self] description in
            SettingsWindow.updateShortcutDescription(description)
            self?.tray?.updateCaptureShortcut(description)
        }
        globalShortcut.start()
        self.globalShortcut = globalShortcut

        // No visible window on launch — a tray-resident app, like the mac menu-bar app.
        let gApp = gobjectCast(app, to: GApplication.self)
        g_application_hold(gApp)
    }

    private func captureArea() {
        guard let connection else { return }
        if AppSettingsStore.shared.useSystemPicker {
            captureWithSystemPicker(connection)
            return
        }
        // Default flow (mirrors macOS: release the mouse and the shot is
        // done): silently grab the whole desktop via the portal — GNOME
        // asks for permission once, then remembers — and crop it in
        // SnapFloat's own frozen-screen overlay.
        // The completion runs synchronously on the GLib main loop thread
        // (the same one driving g_application_run) — no dispatch needed,
        // and DispatchQueue.main isn't integrated with that loop anyway.
        PortalScreenshot.request(on: connection, interactive: false) { [weak self] url in
            guard let self else { return }
            guard let url else {
                // GNOME only lets the *focused* app show the consent dialog,
                // and SnapFloat is a background tray app — so the first-ever
                // silent grab is denied before the user can allow it. Offer
                // a one-time window that re-asks while focused; afterwards
                // (or if declined) fall back to the desktop's own picker.
                if !self.grantPromptShownThisRun {
                    self.grantPromptShownThisRun = true
                    GrantAccessWindow.show(connection: connection, app: self.app) { [weak self] granted in
                        guard let self else { return }
                        if granted {
                            self.captureArea()
                        } else {
                            self.captureWithSystemPicker(connection)
                        }
                    }
                } else {
                    NSLog("SnapFloat: non-interactive screenshot unavailable, falling back to the system picker")
                    self.captureWithSystemPicker(connection)
                }
                return
            }
            CaptureOverlay.show(fullScreenImagePath: url.path) { [weak self] croppedPath, endPoint in
                guard let self, let croppedPath else { return }
                self.handleCapturedImage(at: URL(fileURLWithPath: croppedPath), near: endPoint)
            }
        }
    }

    private func captureWithSystemPicker(_ connection: OpaquePointer) {
        PortalScreenshot.request(on: connection, interactive: true) { [weak self] url in
            guard let self, let url else { return }
            self.handleCapturedImage(at: url, near: nil)
        }
    }

    private func handleCapturedImage(at url: URL, near point: (x: Double, y: Double)?) {
        // The portal drops its file in ~/Pictures/Screenshots and transfers
        // ownership to us — move it into the temp dir so captures don't
        // pile up there. (CaptureOverlay's crops are already in temp; the
        // rename is a harmless no-op move for those.)
        var imagePath = url.path
        let tmpPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("snapfloat-capture-\(UUID().uuidString).png")
        if (try? FileManager.default.moveItem(atPath: imagePath, toPath: tmpPath)) != nil {
            imagePath = tmpPath
        }
        NSLog("SnapFloat: captured \(imagePath)")
        CaptureActions.performConfiguredAction(imagePath: imagePath)
        PreviewWindow.show(imagePath: imagePath, app: app, near: point)
    }

    private func openSettings() {
        SettingsWindow.show(app: app)
    }

    private func quit() {
        let gApp = gobjectCast(app, to: GApplication.self)
        g_application_quit(gApp)
    }
}
