import CGtk4Shim
import Foundation

/// Top-level coordinator: owns the shared D-Bus connection, the tray icon,
/// and wires "Capture Area" through to the portal + floating preview.
final class AppController {
    private let app: UnsafeMutablePointer<GtkApplication>
    private var connection: OpaquePointer?
    private var tray: TrayIndicator?

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

        // No visible window on launch — a tray-resident app, like the mac menu-bar app.
        let gApp = gobjectCast(app, to: GApplication.self)
        g_application_hold(gApp)
    }

    private func captureArea() {
        guard let connection else { return }
        // The completion runs synchronously on the GLib main loop thread
        // (the same one driving g_application_run) — no dispatch needed,
        // and DispatchQueue.main isn't integrated with that loop anyway.
        PortalScreenshot.request(on: connection) { [weak self] url in
            guard let self, let url else { return }
            self.handleCapturedImage(at: url)
        }
    }

    private func handleCapturedImage(at url: URL) {
        NSLog("SnapFloat: captured \(url.path)")
        PreviewWindow.show(imagePath: url.path)
    }

    private func openSettings() {
        SettingsWindow.show(app: app)
    }

    private func quit() {
        let gApp = gobjectCast(app, to: GApplication.self)
        g_application_quit(gApp)
    }
}
