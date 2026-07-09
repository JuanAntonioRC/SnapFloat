import CGtk4Shim
import SnapFloatCore
import Foundation

/// Floating thumbnail shown after a capture, mirroring
/// SnapFloat/ThumbnailWindowController.swift's Copy/Save strip and
/// auto-dismiss timer.
///
/// Known Wayland/GNOME limitation (see README): apps can't set an absolute
/// on-screen position for their own top-level windows under Wayland, so
/// unlike the pinned bottom-right corner placement on macOS, this window
/// appears wherever Mutter's default placement puts it.
enum PreviewWindow {

    private final class Context {
        let imagePath: String
        init(imagePath: String) { self.imagePath = imagePath }
    }

    private static var currentWindow: UnsafeMutablePointer<GtkWindow>?
    private static var timeoutSourceId: CUnsignedInt = 0

    static func show(imagePath: String) {
        dismiss()

        let window = gobjectCast(gtk_window_new(), to: GtkWindow.self)
        gtk_window_set_decorated(window, 0)
        gtk_window_set_default_size(window, 260, 200)
        gtk_window_set_resizable(window, 0)
        gtk_window_set_title(window, "SnapFloat")

        let box = gobjectCast(gtk_box_new(GTK_ORIENTATION_VERTICAL, 4)!, to: GtkBox.self)

        let picture = gtk_picture_new_for_filename(imagePath)
        gtk_widget_set_vexpand(picture, 1)
        gtk_box_append(box, picture)

        let strip = gobjectCast(gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!, to: GtkBox.self)
        gtk_widget_set_halign(gobjectCast(strip, to: GtkWidget.self), GTK_ALIGN_CENTER)
        gtk_widget_set_margin_bottom(gobjectCast(strip, to: GtkWidget.self), 8)
        gtk_widget_set_margin_top(gobjectCast(strip, to: GtkWidget.self), 4)

        let context = Context(imagePath: imagePath)
        let userData = retainedPointer(context)

        let copyBtn = gtk_button_new_with_label("Copy")!
        gConnect(gobjectCast(copyBtn, to: GtkButton.self), "clicked", data: userData, onCopyClicked)
        gtk_box_append(strip, copyBtn)

        let saveBtn = gtk_button_new_with_label("Save")!
        gConnect(gobjectCast(saveBtn, to: GtkButton.self), "clicked", data: userData, onSaveClicked)
        gtk_box_append(strip, saveBtn)

        // Release the retained context once the window (and its buttons) go away.
        gConnect(window, "destroy", data: userData, onWindowDestroy)

        gtk_box_append(box, gobjectCast(strip, to: GtkWidget.self))
        gtk_window_set_child(window, gobjectCast(box, to: GtkWidget.self))
        gtk_window_present(window)

        currentWindow = window

        let duration = UInt32(max(1, AppSettingsStore.shared.previewDuration))
        timeoutSourceId = g_timeout_add(duration * 1000, dismissTimeoutCallback, nil)
    }

    static func dismiss() {
        if timeoutSourceId != 0 {
            g_source_remove(timeoutSourceId)
            timeoutSourceId = 0
        }
        if let currentWindow {
            gtk_window_destroy(currentWindow)
        }
        currentWindow = nil
    }

    private static let dismissTimeoutCallback: GSourceFunc = { _ in
        PreviewWindow.dismiss()
        return 0 // G_SOURCE_REMOVE
    }

    private static let onWindowDestroy: GSimpleHandler = { _, userData in
        guard let userData else { return }
        _ = takeRetained(userData, as: Context.self)
    }

    private static let onCopyClicked: GSimpleHandler = { _, userData in
        guard let userData else { return }
        let context = unretained(userData, as: Context.self)
        copyToClipboard(imagePath: context.imagePath)
        dismiss()
    }

    private static let onSaveClicked: GSimpleHandler = { _, userData in
        guard let userData else { return }
        let context = unretained(userData, as: Context.self)
        saveToDisk(imagePath: context.imagePath)
        dismiss()
    }

    private static func copyToClipboard(imagePath: String) {
        var error: UnsafeMutablePointer<GError>?
        guard let texture = imagePath.withCString({ gdk_texture_new_from_filename($0, &error) }) else {
            if let error { NSLog("SnapFloat: copy failed – \(String(cString: error.pointee.message))") }
            return
        }
        guard let display = gdk_display_get_default() else { return }
        let clipboard = gdk_display_get_clipboard(display)
        gdk_clipboard_set_texture(clipboard, texture)
    }

    private static func saveToDisk(imagePath: String) {
        guard let dir = AppSettingsStore.shared.saveDirectoryPath else { return }
        let destination = (dir as NSString).appendingPathComponent(ScreenshotFileNamer.makeFilename())
        do {
            try FileManager.default.copyItem(atPath: imagePath, toPath: destination)
            LinuxNotifications.postSaveNotification(path: destination)
        } catch {
            NSLog("SnapFloat: save failed – \(error)")
        }
    }
}
