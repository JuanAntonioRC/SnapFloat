import CGtk4Shim
import Foundation

/// Save-complete notifications via GNotification, mirroring
/// SnapFloat/SettingsManager.swift's postSaveNotification on macOS.
enum LinuxNotifications {
    private static var app: UnsafeMutablePointer<GApplication>?

    static func configure(app: UnsafeMutablePointer<GtkApplication>) {
        self.app = gobjectCast(app, to: GApplication.self)
    }

    static func postSaveNotification(path: String) {
        guard let app else { return }
        let notification = g_notification_new("Screenshot saved")
        let filename = (path as NSString).lastPathComponent
        filename.withCString { g_notification_set_body(notification, $0) }
        "snapfloat-save".withCString { id in
            g_application_send_notification(app, id, notification)
        }
    }
}
