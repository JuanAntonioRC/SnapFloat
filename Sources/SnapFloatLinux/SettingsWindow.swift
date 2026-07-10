import CGtk4Shim
import SnapFloatCore
import Foundation

/// Preferences window, mirroring SnapFloat/SettingsWindowController.swift.
/// Unlike macOS's in-app shortcut recorder, the key combination for the
/// global shortcut is assigned in GNOME's own Settings app — see
/// GlobalShortcut.swift for why.
///
/// Note: GtkLabel/GtkComboBoxText/GtkFileDialog are usable via Swift type
/// *inference* (e.g. `let l = gtk_label_new(...)`) but the bare type names
/// don't resolve when spelled out explicitly (`UnsafeMutablePointer<GtkLabel>`
/// errors "cannot find type in scope") — an odd but reproducible
/// ClangImporter quirk for this GTK version. Functions taking one of these
/// as `self` (gtk_label_set_text, gtk_combo_box_text_append_text, ...)
/// import that parameter as `OpaquePointer` instead, which is what's used
/// below wherever one of these three is involved. GtkFileDialog's
/// constructor itself already returns `OpaquePointer` (it's not a GtkWidget
/// subclass), so it needs no conversion at all.
enum SettingsWindow {

    private final class Context {
        var pathLabel: UnsafeMutablePointer<GtkWidget>!
        var shortcutLabel: UnsafeMutablePointer<GtkWidget>!
        var window: UnsafeMutablePointer<GtkWindow>!
        var pendingFolderDialog: OpaquePointer!
    }

    private static var current: UnsafeMutablePointer<GtkWindow>?
    private static var currentContext: Context?

    /// The global shortcut's current key combination, pushed by AppController
    /// whenever GlobalShortcut learns/changes it. Held here so every code
    /// path that opens Settings (tray, preview, annotation editor) shows it.
    private(set) static var shortcutDescription: String?

    static func updateShortcutDescription(_ description: String?) {
        shortcutDescription = description
        if let context = currentContext {
            shortcutLabelText.withCString { gtk_label_set_text(OpaquePointer(context.shortcutLabel), $0) }
        }
    }

    private static var shortcutLabelText: String {
        shortcutDescription ?? "Not set — first launch needs a one-time GNOME permission prompt"
    }

    static func show(app: UnsafeMutablePointer<GtkApplication>) {
        if let current {
            gtk_window_present(current)
            return
        }

        let settings = AppSettingsStore.shared
        let window = gobjectCast(gtk_application_window_new(app)!, to: GtkWindow.self)
        gtk_window_set_title(window, "SnapFloat — Settings")
        gtk_window_set_default_size(window, 420, 360)

        let root = gobjectCast(gtk_box_new(GTK_ORIENTATION_VERTICAL, 12)!, to: GtkBox.self)
        gtk_widget_set_margin_start(gobjectCast(root, to: GtkWidget.self), 16)
        gtk_widget_set_margin_end(gobjectCast(root, to: GtkWidget.self), 16)
        gtk_widget_set_margin_top(gobjectCast(root, to: GtkWidget.self), 16)
        gtk_widget_set_margin_bottom(gobjectCast(root, to: GtkWidget.self), 16)

        let context = Context()
        context.window = window
        let userData = retainedPointer(context)
        gConnect(window, "destroy", data: userData, onWindowDestroy)

        // Shortcut
        addSectionLabel("Shortcut", to: root)
        let shortcutRow = gobjectCast(gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)!, to: GtkBox.self)
        let shortcutLabel = gtk_label_new(shortcutLabelText)!
        context.shortcutLabel = shortcutLabel
        gtk_label_set_ellipsize(OpaquePointer(shortcutLabel), PANGO_ELLIPSIZE_END)
        gtk_widget_set_hexpand(shortcutLabel, 1)
        gtk_widget_set_halign(shortcutLabel, GTK_ALIGN_START)
        gtk_box_append(shortcutRow, shortcutLabel)
        let shortcutBtn = gtk_button_new_with_label("Open Keyboard Shortcuts…")!
        gConnect(shortcutBtn, "clicked", onOpenKeyboardShortcutsClicked)
        gtk_box_append(shortcutRow, shortcutBtn)
        gtk_box_append(root, gobjectCast(shortcutRow, to: GtkWidget.self))

        // On capture
        addSectionLabel("On capture", to: root)
        let captureCombo = gtk_combo_box_text_new()!
        for title in ["Copy to clipboard", "Do nothing", "Save to folder", "Copy to clipboard & save to folder"] {
            title.withCString { gtk_combo_box_text_append_text(OpaquePointer(captureCombo), $0) }
        }
        gtk_combo_box_set_active(gobjectCast(captureCombo, to: GtkComboBox.self), Int32(settings.captureAction.rawValue))
        gConnect(captureCombo, "changed", onCaptureActionChanged)
        gtk_box_append(root, captureCombo)

        let pickerCheck = gobjectCast(
            gtk_check_button_new_with_label("Use GNOME's screenshot dialog (adds window & full-screen capture)")!,
            to: GtkCheckButton.self)
        gtk_check_button_set_active(pickerCheck, settings.useSystemPicker ? 1 : 0)
        gConnect(pickerCheck, "toggled", onPickerToggled)
        gtk_box_append(root, gobjectCast(pickerCheck, to: GtkWidget.self))

        // Preview duration
        addSectionLabel("Preview duration (seconds)", to: root)
        let durationScale = gobjectCast(
            gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 1, 30, 1)!, to: GtkRange.self)
        gtk_range_set_value(durationScale, settings.previewDuration)
        gConnect(durationScale, "value-changed", onDurationChanged)
        gtk_box_append(root, gobjectCast(durationScale, to: GtkWidget.self))

        // Save location
        addSectionLabel("Save location", to: root)
        let autoSaveCheck = gobjectCast(gtk_check_button_new_with_label("Enable saving to disk")!, to: GtkCheckButton.self)
        gtk_check_button_set_active(autoSaveCheck, settings.autoSaveEnabled ? 1 : 0)
        gConnect(autoSaveCheck, "toggled", onAutoSaveToggled)
        gtk_box_append(root, gobjectCast(autoSaveCheck, to: GtkWidget.self))

        let pathRow = gobjectCast(gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)!, to: GtkBox.self)
        let pathLabel = gtk_label_new(settings.saveLocation ?? "No folder selected")!
        gtk_label_set_ellipsize(OpaquePointer(pathLabel), PANGO_ELLIPSIZE_MIDDLE)
        gtk_widget_set_hexpand(pathLabel, 1)
        gtk_widget_set_halign(pathLabel, GTK_ALIGN_START)
        context.pathLabel = pathLabel
        gtk_box_append(pathRow, pathLabel)

        let browseBtn = gtk_button_new_with_label("Choose…")!
        gConnect(browseBtn, "clicked", data: userData, onBrowseClicked)
        gtk_box_append(pathRow, browseBtn)
        gtk_box_append(root, gobjectCast(pathRow, to: GtkWidget.self))

        // General
        addSectionLabel("General", to: root)
        let launchCheck = gobjectCast(gtk_check_button_new_with_label("Launch at login")!, to: GtkCheckButton.self)
        gtk_check_button_set_active(launchCheck, LinuxAutostart.isEnabled ? 1 : 0)
        gConnect(launchCheck, "toggled", onLaunchToggled)
        gtk_box_append(root, gobjectCast(launchCheck, to: GtkWidget.self))

        gtk_window_set_child(window, gobjectCast(root, to: GtkWidget.self))
        gtk_window_present(window)
        current = window
        currentContext = context
    }

    private static func addSectionLabel(_ text: String, to box: UnsafeMutablePointer<GtkBox>) {
        let label = gtk_label_new(text)!
        gtk_widget_set_halign(label, GTK_ALIGN_START)
        gtk_widget_add_css_class(label, "heading")
        gtk_box_append(box, label)
    }

    // MARK: - Handlers

    private static let onWindowDestroy: GSimpleHandler = { _, userData in
        current = nil
        currentContext = nil
        guard let userData else { return }
        _ = takeRetained(userData, as: Context.self)
    }

    private static let onCaptureActionChanged: GSimpleHandler = { widgetPtr, _ in
        guard let widgetPtr else { return }
        let combo = widgetPtr.assumingMemoryBound(to: GtkComboBox.self)
        let index = gtk_combo_box_get_active(combo)
        if let action = CaptureAction(rawValue: Int(index)) {
            AppSettingsStore.shared.captureAction = action
        }
    }

    private static let onDurationChanged: GSimpleHandler = { widgetPtr, _ in
        guard let widgetPtr else { return }
        let range = widgetPtr.assumingMemoryBound(to: GtkRange.self)
        AppSettingsStore.shared.previewDuration = gtk_range_get_value(range)
    }

    private static let onPickerToggled: GSimpleHandler = { widgetPtr, _ in
        guard let widgetPtr else { return }
        let check = widgetPtr.assumingMemoryBound(to: GtkCheckButton.self)
        AppSettingsStore.shared.useSystemPicker = gtk_check_button_get_active(check) != 0
    }

    private static let onAutoSaveToggled: GSimpleHandler = { widgetPtr, _ in
        guard let widgetPtr else { return }
        let check = widgetPtr.assumingMemoryBound(to: GtkCheckButton.self)
        AppSettingsStore.shared.autoSaveEnabled = gtk_check_button_get_active(check) != 0
    }

    private static let onLaunchToggled: GSimpleHandler = { widgetPtr, _ in
        guard let widgetPtr else { return }
        let check = widgetPtr.assumingMemoryBound(to: GtkCheckButton.self)
        LinuxAutostart.isEnabled = gtk_check_button_get_active(check) != 0
    }

    private static let onOpenKeyboardShortcutsClicked: GSimpleHandler = { _, _ in
        var error: UnsafeMutablePointer<GError>?
        _ = "gnome-control-center keyboard".withCString { g_spawn_command_line_async($0, &error) }
        if let error {
            NSLog("SnapFloat: could not open Keyboard Settings – \(String(cString: error.pointee.message))")
        }
    }

    private static let onBrowseClicked: GSimpleHandler = { _, userData in
        guard let userData else { return }
        let context = unretained(userData, as: Context.self)
        let dialog = gtk_file_dialog_new()!
        context.pendingFolderDialog = dialog
        gtk_file_dialog_select_folder(dialog, context.window, nil, onFolderChosen, retainedPointer(context))
    }

    private static let onFolderChosen: GAsyncReadyCallback = { _, result, userData in
        guard let userData, let result else { return }
        let context = takeRetained(userData, as: Context.self)
        var error: UnsafeMutablePointer<GError>?
        let file = gtk_file_dialog_select_folder_finish(context.pendingFolderDialog, result, &error)
        g_object_unref(UnsafeMutableRawPointer(context.pendingFolderDialog))
        context.pendingFolderDialog = nil
        guard let file else { return }
        defer { g_object_unref(UnsafeMutableRawPointer(file)) }
        guard let pathPtr = g_file_get_path(file) else { return }
        let path = String(cString: pathPtr)
        g_free(pathPtr)
        AppSettingsStore.shared.saveLocation = path
        AppSettingsStore.shared.autoSaveEnabled = true
        path.withCString { gtk_label_set_text(OpaquePointer(context.pathLabel), $0) }
    }
}
