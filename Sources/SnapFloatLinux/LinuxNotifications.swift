import CGtk4Shim
import Foundation

/// Save-complete notifications via GNotification, mirroring
/// SnapFloat/SettingsManager.swift's postSaveNotification on macOS —
/// including a "Show in Files" button (macOS's "Show in Finder").
enum LinuxNotifications {
    private static var app: UnsafeMutablePointer<GApplication>?

    private typealias ActionHandler = @convention(c) (
        UnsafeMutableRawPointer?, // GSimpleAction*
        OpaquePointer?,           // GVariant* parameter
        UnsafeMutableRawPointer?  // user_data
    ) -> Void

    static func configure(app: UnsafeMutablePointer<GtkApplication>) {
        let gApp = gobjectCast(app, to: GApplication.self)
        self.app = gApp

        // App-scoped action the notification button activates, carrying the
        // saved file's path as its string parameter.
        guard let action = "show-in-files".withCString({
            g_simple_action_new($0, g_variant_type_new("s"))
        }) else { return }
        _ = "activate".withCString { sig in
            g_signal_connect_data(
                UnsafeMutableRawPointer(action), sig,
                unsafeBitCast(onShowInFiles, to: GCallback.self),
                nil, nil, GConnectFlags(rawValue: 0)
            )
        }
        g_action_map_add_action(OpaquePointer(gApp), action)
    }

    static func postSaveNotification(path: String) {
        guard let app else { return }
        let notification = g_notification_new("Screenshot saved")
        let filename = (path as NSString).lastPathComponent
        filename.withCString { g_notification_set_body(notification, $0) }
        "Show in Files".withCString { label in
            "app.show-in-files".withCString { action in
                g_notification_add_button_with_target_value(notification, label, action, gvString(path))
            }
        }
        "snapfloat-save".withCString { id in
            g_application_send_notification(app, id, notification)
        }
    }

    private static let onShowInFiles: ActionHandler = { _, parameter, _ in
        guard let parameter, let cstr = g_variant_get_string(parameter, nil) else { return }
        showInFiles(path: String(cString: cstr))
    }

    /// Asks the file manager to reveal the saved screenshot via the standard
    /// org.freedesktop.FileManager1 interface (Nautilus implements it);
    /// mirrors NSWorkspace.activateFileViewerSelecting on macOS.
    private static func showInFiles(path: String) {
        guard let app, let connection = g_application_get_dbus_connection(app) else { return }
        let uri = URL(fileURLWithPath: path).absoluteString
        let params = gvTuple([gvArray(type: "as", [gvString(uri)]), gvString("")])
        g_dbus_connection_call(
            connection,
            "org.freedesktop.FileManager1",
            "/org/freedesktop/FileManager1",
            "org.freedesktop.FileManager1",
            "ShowItems",
            params, nil, GDBusCallFlags(rawValue: 0), -1, nil, nil, nil
        )
    }
}
