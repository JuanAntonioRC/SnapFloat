import CGtk4Shim
import SnapFloatCore
import Foundation

/// Floating thumbnail shown after a capture, mirroring
/// SnapFloat/ThumbnailWindowController.swift's Copy/Save strip and
/// auto-dismiss timer.
///
/// On X11/XWayland (the preferred backend, see main.swift) the window is
/// pinned to the bottom-right corner of the capture's monitor via the EWMH
/// pager protocol, floats above other windows, and — like macOS's
/// .nonactivatingPanel — never steals keyboard focus when it appears (see
/// X11Interop.swift). On pure Wayland there is no way to self-position
/// (Mutter has no layer-shell), so it falls back to default placement.
enum PreviewWindow {

    private final class Context {
        let imagePath: String
        let app: UnsafeMutablePointer<GtkApplication>
        init(imagePath: String, app: UnsafeMutablePointer<GtkApplication>) {
            self.imagePath = imagePath
            self.app = app
        }
    }

    private static var currentWindow: UnsafeMutablePointer<GtkWindow>?
    private static var timeoutSourceId: CUnsignedInt = 0
    private static var pendingPinMonitor: GdkRectangle?

    /// Runs shortly after present(): by then Mutter manages the window and
    /// its surface has its real size (a pre-map gtk_widget_measure can
    /// overshoot), so the EWMH move lands exactly; then the window is
    /// revealed. GDK sizes/monitor geometry are logical pixels while X root
    /// coordinates are physical, hence the scale-factor multiply.
    private static let pinTimeoutCallback: GSourceFunc = { _ in
        if let window = currentWindow, let mon = pendingPinMonitor {
            let widget = gobjectCast(window, to: GtkWidget.self)
            var w: Int32 = 220, h: Int32 = 200
            if let native = gtk_widget_get_native(widget),
               let surface = gtk_native_get_surface(native) {
                w = gdk_surface_get_width(surface)
                h = gdk_surface_get_height(surface)
            }
            let margin: Int32 = 20
            let sf = max(gtk_widget_get_scale_factor(widget), 1)
            X11Interop.ewmhMove(window,
                                x: (mon.x + mon.width - w - margin) * sf,
                                y: (mon.y + mon.height - h - margin) * sf)
            X11Interop.keepAbove(window)
            gtk_widget_set_opacity(widget, 1)
        }
        pendingPinMonitor = nil
        return 0 // G_SOURCE_REMOVE
    }

    /// - Parameter point: where the selection ended, in root coordinates —
    ///   used to pick the monitor whose corner gets the preview (macOS shows
    ///   it on the capture screen). nil = primary monitor.
    static func show(imagePath: String, app: UnsafeMutablePointer<GtkApplication>,
                     near point: (x: Double, y: Double)? = nil) {
        dismiss()

        let window = gobjectCast(gtk_window_new(), to: GtkWindow.self)
        gtk_window_set_decorated(window, 0)
        gtk_window_set_resizable(window, 0)
        gtk_window_set_title(window, "SnapFloat")

        let box = gobjectCast(gtk_box_new(GTK_ORIENTATION_VERTICAL, 4)!, to: GtkBox.self)

        // Size the thumbnail to the capture's aspect ratio (longest edge
        // 200px, floor 40px), mirroring ThumbnailWindowController on macOS,
        // and paint it in a GtkDrawingArea of exactly that size. Neither
        // stock image widget can do this: GtkPicture's height-for-width
        // measure re-inflates with the aspect ratio whenever the box is
        // wider than the thumb (ballooning the window, which always adopts
        // its child's natural size when non-resizable), and GtkImage renders
        // paintables at *icon* size, a tiny 16px glyph. The pixbuf is loaded
        // at scale-factor × thumb size so it stays crisp on HiDPI.
        var thumbW = 220.0, thumbH = 160.0
        var picture = gtk_picture_new_for_filename(imagePath)! // fallback if the pixbuf load fails
        var imgW: Int32 = 0, imgH: Int32 = 0
        if imagePath.withCString({ gdk_pixbuf_get_file_info($0, &imgW, &imgH) }) != nil,
           imgW > 0, imgH > 0 {
            let maxEdge = 200.0
            let scale = min(maxEdge / Double(imgW), maxEdge / Double(imgH), 1.0)
            thumbW = max(Double(imgW) * scale, 40)
            thumbH = max(Double(imgH) * scale, 40)
            let renderScale = displayScaleFactor()
            var error: UnsafeMutablePointer<GError>?
            if let pixbuf = imagePath.withCString({
                gdk_pixbuf_new_from_file_at_scale($0, Int32(thumbW) * renderScale,
                                                  Int32(thumbH) * renderScale, 1, &error)
            }) {
                let areaWidget = gtk_drawing_area_new()!
                let area = gobjectCast(areaWidget, to: GtkDrawingArea.self)
                gtk_drawing_area_set_content_width(area, Int32(thumbW))
                gtk_drawing_area_set_content_height(area, Int32(thumbH))
                // The draw func owns the pixbuf reference; released via the
                // destroy notify when the area goes away.
                gtk_drawing_area_set_draw_func(area, drawThumbnail,
                                               UnsafeMutableRawPointer(pixbuf),
                                               { data in if let data { g_object_unref(data) } })
                picture = areaWidget
            }
        }
        gtk_widget_set_size_request(picture, Int32(thumbW), Int32(thumbH))
        gtk_widget_set_vexpand(picture, 1)
        // Width floor so the Copy/Save strip always fits.
        gtk_widget_set_size_request(gobjectCast(box, to: GtkWidget.self), 180, -1)
        gtk_box_append(box, picture)

        let strip = gobjectCast(gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!, to: GtkBox.self)
        gtk_widget_set_halign(gobjectCast(strip, to: GtkWidget.self), GTK_ALIGN_CENTER)
        gtk_widget_set_margin_bottom(gobjectCast(strip, to: GtkWidget.self), 8)
        gtk_widget_set_margin_top(gobjectCast(strip, to: GtkWidget.self), 4)

        let context = Context(imagePath: imagePath, app: app)
        let userData = retainedPointer(context)

        // Click the thumbnail itself to open the annotation editor, mirroring
        // ThumbnailWindowController's ClickableView on macOS.
        let clickGesture = gtk_gesture_click_new()!
        gConnect(clickGesture, "pressed", data: userData, onPictureClicked)
        gtk_widget_add_controller(picture, clickGesture)

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

        if X11Interop.isX11, let mon = monitorRect(near: point) {
            // Pin bottom-right of the capture's monitor: no focus steal on
            // map, EWMH-moved into the corner once the WM manages it, kept
            // above other windows. Mapped invisible and revealed after the
            // move so it doesn't flash at Mutter's default placement.
            let widget = gobjectCast(window, to: GtkWidget.self)
            gtk_widget_realize(widget)
            X11Interop.setNoFocusOnMap(window)
            pendingPinMonitor = mon
            gtk_widget_set_opacity(widget, 0)
            gtk_window_present(window)
            _ = g_timeout_add(30, pinTimeoutCallback, nil)
        } else {
            gtk_window_present(window)
        }

        currentWindow = window

        let duration = UInt32(max(1, AppSettingsStore.shared.previewDuration))
        timeoutSourceId = g_timeout_add(duration * 1000, dismissTimeoutCallback, nil)
    }

    private typealias DrawFn = @convention(c) (
        UnsafeMutablePointer<GtkDrawingArea>?, OpaquePointer?, Int32, Int32, UnsafeMutableRawPointer?
    ) -> Void

    /// Paints the pre-scaled thumbnail pixbuf (user data) fitted into the
    /// widget, centered. The pixbuf is larger than the widget by the display
    /// scale factor, so the fit-down renders it 1:1 in physical pixels.
    private static let drawThumbnail: DrawFn = { _, cr, width, height, userData in
        guard let cr, let userData else { return }
        let pixbuf = OpaquePointer(userData)
        let pw = Double(gdk_pixbuf_get_width(pixbuf))
        let ph = Double(gdk_pixbuf_get_height(pixbuf))
        guard pw > 0, ph > 0, width > 0, height > 0 else { return }
        let fit = min(Double(width) / pw, Double(height) / ph)
        cairo_translate(cr, (Double(width) - pw * fit) / 2, (Double(height) - ph * fit) / 2)
        cairo_scale(cr, fit, fit)
        gdk_cairo_set_source_pixbuf(cr, pixbuf, 0, 0)
        cairo_paint(cr)
    }

    /// Integer scale factor of the (first) monitor — 2 on HiDPI.
    private static func displayScaleFactor() -> Int32 {
        guard let display = gdk_display_get_default(),
              let monitors = gdk_display_get_monitors(display),
              g_list_model_get_n_items(monitors) > 0,
              let item = g_list_model_get_item(monitors, 0) else { return 1 }
        defer { g_object_unref(item) }
        return max(gdk_monitor_get_scale_factor(OpaquePointer(item)), 1)
    }

    /// Workarea of the monitor containing `point` (GDK logical root coords),
    /// or the first monitor's when the point is nil / outside every monitor.
    /// The workarea (not the raw geometry) matters for the pin: docks and
    /// panels reserve struts, and Mutter clamps windows into the workarea
    /// anyway — pinning to the geometry corner would eat the margin and
    /// shove the preview flush against the dock.
    private static func monitorRect(near point: (x: Double, y: Double)?) -> GdkRectangle? {
        guard let display = gdk_display_get_default(),
              let monitors = gdk_display_get_monitors(display) else { return nil }
        var first: GdkRectangle?
        for i in 0..<g_list_model_get_n_items(monitors) {
            guard let item = g_list_model_get_item(monitors, i) else { continue }
            defer { g_object_unref(item) }
            var rect = GdkRectangle()
            gdk_monitor_get_geometry(OpaquePointer(item), &rect)
            var workarea = GdkRectangle()
            gdk_x11_monitor_get_workarea(OpaquePointer(item), &workarea)
            if first == nil { first = workarea }
            if let point,
               Int32(point.x) >= rect.x, Int32(point.x) < rect.x + rect.width,
               Int32(point.y) >= rect.y, Int32(point.y) < rect.y + rect.height {
                return workarea
            }
        }
        return first
    }

    static func dismiss() {
        cancelAutoDismiss()
        if let currentWindow {
            gtk_window_destroy(currentWindow)
        }
        currentWindow = nil
    }

    private static func cancelAutoDismiss() {
        if timeoutSourceId != 0 {
            g_source_remove(timeoutSourceId)
            timeoutSourceId = 0
        }
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
        CaptureActions.copyToClipboard(imagePath: context.imagePath)
        dismiss()
    }

    private static let onSaveClicked: GSimpleHandler = { _, userData in
        guard let userData else { return }
        let context = unretained(userData, as: Context.self)
        guard AppSettingsStore.shared.saveDirectoryPath != nil else {
            // Mirror macOS's saveTapped: no folder configured yet → open
            // Settings and keep the preview around (auto-dismiss cancelled)
            // so Save can be retried after picking a folder.
            cancelAutoDismiss()
            SettingsWindow.show(app: context.app)
            return
        }
        CaptureActions.saveToDisk(imagePath: context.imagePath)
        dismiss()
    }

    private typealias ClickHandler = @convention(c) (OpaquePointer?, Int32, Double, Double, UnsafeMutableRawPointer?) -> Void

    private static let onPictureClicked: ClickHandler = { _, _, _, _, userData in
        guard let userData else { return }
        let context = unretained(userData, as: Context.self)
        let imagePath = context.imagePath
        let app = context.app
        dismiss()
        AnnotationWindow.show(imagePath: imagePath, app: app)
    }
}
