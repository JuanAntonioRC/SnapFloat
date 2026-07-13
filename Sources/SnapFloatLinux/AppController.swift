import CGtk4Shim
import SnapFloatCore
import Foundation

/// Top-level coordinator: owns the shared D-Bus connection, the tray icon,
/// and wires "Capture Area" through to the portal + floating preview.
final class AppController {
    private let app: UnsafeMutablePointer<GApplication>
    private var connection: OpaquePointer?
    private var tray: TrayIndicator?
    private var grantPromptShownThisRun = false

    init(app: UnsafeMutablePointer<GApplication>) {
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

        GlobalHotkey.shared.onDescriptionChanged = { [weak self] description in
            SettingsWindow.updateShortcutDescription(description)
            self?.tray?.updateCaptureShortcut(description)
        }
        GlobalHotkey.shared.start { [weak self] in self?.captureArea() }

        // No visible window on launch — a tray-resident app, like the mac menu-bar app.
        g_application_hold(app)
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
                    GrantAccessWindow.show(connection: connection) { [weak self] granted in
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
        // performConfiguredAction's copy-to-clipboard action touches the GDK
        // clipboard/display directly, and — on the system-picker path (no
        // CaptureOverlay of ours involved) — may run before any window of
        // ours has opened GTK yet. PreviewWindow.show below would init it
        // anyway, but only after the copy already needed it.
        GtkLazyInit.ensureGtkInitialized()

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
        PreviewWindow.show(imagePath: imagePath, near: point)
    }

    private func openSettings() {
        SettingsWindow.show()
    }

    private func quit() {
        g_application_quit(app)
    }
}
