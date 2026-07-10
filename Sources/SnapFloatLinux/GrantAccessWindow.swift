import CGtk4Shim
import Foundation

/// One-time helper for the silent-capture permission.
///
/// The instant-capture flow needs GNOME's remembered "allow screenshots"
/// consent, but GNOME only lets the *focused* app pop that consent dialog —
/// and SnapFloat is a background tray app with no focused window at capture
/// time, so the first silent grab is denied outright. This window fixes
/// that: it explains the situation, and its button re-issues the portal
/// request while SnapFloat *is* the focused app (with a proper parent
/// handle), so the consent dialog can appear. GNOME remembers the answer,
/// and every later capture is instant with no dialog at all.
enum GrantAccessWindow {

    private final class Context {
        var window: UnsafeMutablePointer<GtkWindow>!
        var connection: OpaquePointer!
        var finished = false
        var onFinished: ((Bool) -> Void)!
    }

    private static var current: Context?

    static func show(connection: OpaquePointer,
                     app: UnsafeMutablePointer<GtkApplication>,
                     onFinished: @escaping (Bool) -> Void) {
        if let current { gtk_window_destroy(current.window) }

        let context = Context()
        context.connection = connection
        context.onFinished = onFinished

        let window = gobjectCast(gtk_application_window_new(app)!, to: GtkWindow.self)
        gtk_window_set_title(window, "SnapFloat — Screenshot access")
        gtk_window_set_resizable(window, 0)
        context.window = window

        let userData = retainedPointer(context)
        gConnect(window, "destroy", data: userData, onWindowDestroy)

        let root = gobjectCast(gtk_box_new(GTK_ORIENTATION_VERTICAL, 12)!, to: GtkBox.self)
        for setMargin in [gtk_widget_set_margin_start, gtk_widget_set_margin_end,
                          gtk_widget_set_margin_top, gtk_widget_set_margin_bottom] {
            setMargin(gobjectCast(root, to: GtkWidget.self), 16)
        }

        let label = gtk_label_new(
            "SnapFloat can capture instantly — drag a region and release, with no " +
            "GNOME dialog every time — once you allow it to take screenshots.\n\n" +
            "GNOME will ask once and remember your answer.")!
        gtk_label_set_wrap(OpaquePointer(label), 1)
        gtk_label_set_max_width_chars(OpaquePointer(label), 46)
        gtk_widget_set_halign(label, GTK_ALIGN_START)
        gtk_box_append(root, label)

        let buttonRow = gobjectCast(gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)!, to: GtkBox.self)
        gtk_widget_set_halign(gobjectCast(buttonRow, to: GtkWidget.self), GTK_ALIGN_END)

        let skipBtn = gtk_button_new_with_label("Use GNOME's dialog")!
        gConnect(skipBtn, "clicked", data: userData, onSkipClicked)
        gtk_box_append(buttonRow, skipBtn)

        let grantBtn = gtk_button_new_with_label("Allow screenshots…")!
        gtk_widget_add_css_class(grantBtn, "suggested-action")
        gConnect(grantBtn, "clicked", data: userData, onGrantClicked)
        gtk_box_append(buttonRow, grantBtn)

        gtk_box_append(root, gobjectCast(buttonRow, to: GtkWidget.self))
        gtk_window_set_child(window, gobjectCast(root, to: GtkWidget.self))
        gtk_window_present(window)
        current = context
    }

    // MARK: - Handlers

    private static let onGrantClicked: GSimpleHandler = { _, userData in
        guard let userData else { return }
        let context = unretained(userData, as: Context.self)
        // Re-request from this (focused) window — now GNOME may show its
        // consent dialog. The grabbed image is a throwaway; the real
        // capture flow re-runs on success.
        PortalScreenshot.request(on: context.connection, interactive: false,
                                 parentWindow: X11Interop.portalParentHandle(context.window)) { url in
            if let url { try? FileManager.default.removeItem(atPath: url.path) }
            finish(context, granted: url != nil)
        }
    }

    private static let onSkipClicked: GSimpleHandler = { _, userData in
        guard let userData else { return }
        finish(unretained(userData, as: Context.self), granted: false)
    }

    private static func finish(_ context: Context, granted: Bool) {
        guard !context.finished else { return }
        context.finished = true
        let onFinished = context.onFinished!
        gtk_window_destroy(context.window)
        onFinished(granted)
    }

    private static let onWindowDestroy: GSimpleHandler = { _, userData in
        current = nil
        guard let userData else { return }
        let context = takeRetained(userData, as: Context.self)
        // Closing the window without choosing counts as "not now".
        if !context.finished {
            context.finished = true
            context.onFinished(false)
        }
    }
}
