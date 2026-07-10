import CGtk4Shim
import Glibc
import Foundation

/// SnapFloat's own region picker, mirroring macOS's CaptureOverlayWindow —
/// and the same trick Flameshot uses on GNOME/Wayland: the portal has
/// already grabbed the *whole* desktop non-interactively, and this overlay
/// shows that frozen screenshot fullscreen with a dimmer, crosshair and a
/// live size label. Releasing the mouse completes the capture immediately —
/// no Enter, no GNOME dialog. Escape or right-click cancels.
///
/// The window is a regular managed fullscreen window (unmanaged/
/// override-redirect windows never receive pointer input from Mutter — see
/// X11Interop.swift), shown on the monitor holding the pointer. The portal
/// image spans all monitors; this overlay shows and crops that monitor's
/// slice. Multi-monitor selections spanning screens aren't supported — the
/// "Use GNOME's screenshot dialog" setting covers that case.
enum CaptureOverlay {

    private final class Context {
        var window: UnsafeMutablePointer<GtkWindow>!
        var areaWidget: UnsafeMutablePointer<GtkWidget>!
        var surface: OpaquePointer!

        // The monitor's slice of the portal image, in image pixels.
        var subX: Double = 0
        var subY: Double = 0
        var subW: Double = 0
        var subH: Double = 0
        // Monitor origin in GDK root coords (for the preview-placement hint).
        var monX: Double = 0
        var monY: Double = 0
        var monW: Double = 1
        // Image pixels per widget pixel, refreshed on each draw.
        var imgPerWidgetX: Double = 1
        var imgPerWidgetY: Double = 1
        var widgetW: Double = 1

        var selecting = false
        var selStart: (x: Double, y: Double) = (0, 0)
        var selEnd: (x: Double, y: Double) = (0, 0)

        var finished = false
        /// (cropped PNG path or nil if cancelled, selection end in GDK root coords)
        var onDone: ((String?, (x: Double, y: Double)?) -> Void)!
    }

    private static var current: Context?

    /// Takes ownership of `fullScreenImagePath` (the portal's file) — it is
    /// deleted as soon as it's loaded.
    static func show(fullScreenImagePath: String,
                     onDone: @escaping (String?, (x: Double, y: Double)?) -> Void) {
        if let current { gtk_window_destroy(current.window) }

        let surface = fullScreenImagePath.withCString { cairo_image_surface_create_from_png($0) }
        try? FileManager.default.removeItem(atPath: fullScreenImagePath)
        let imgW = surface.map { Double(cairo_image_surface_get_width($0)) } ?? 0
        let imgH = surface.map { Double(cairo_image_surface_get_height($0)) } ?? 0
        guard let surface, imgW > 0, imgH > 0 else {
            if let surface { cairo_surface_destroy(surface) }
            NSLog("SnapFloat: capture overlay could not load \(fullScreenImagePath)")
            onDone(nil, nil)
            return
        }

        let context = Context()
        context.surface = surface
        context.onDone = onDone

        let window = gobjectCast(gtk_window_new(), to: GtkWindow.self)
        gtk_window_set_decorated(window, 0)
        gtk_window_set_title(window, "SnapFloat — Capture")
        context.window = window

        let userData = retainedPointer(context)
        gConnect(window, "destroy", data: userData, onWindowDestroy)

        let areaWidget = gtk_drawing_area_new()!
        context.areaWidget = areaWidget
        gtk_widget_set_cursor_from_name(areaWidget, "crosshair")
        let area = gobjectCast(areaWidget, to: GtkDrawingArea.self)
        gtk_drawing_area_set_draw_func(area, drawFunc, userData, nil)

        let drag = gtk_gesture_drag_new()!
        gConnect(drag, "drag-begin", data: userData, onDragBegin)
        gConnect(drag, "drag-update", data: userData, onDragUpdate)
        gConnect(drag, "drag-end", data: userData, onDragEnd)
        gtk_widget_add_controller(areaWidget, drag)

        // Right-click cancels, like Flameshot.
        let rightClick = gtk_gesture_click_new()!
        gtk_gesture_single_set_button(rightClick, 3)
        gConnect(rightClick, "pressed", data: userData, onRightClick)
        gtk_widget_add_controller(areaWidget, rightClick)

        let keys = gtk_event_controller_key_new()!
        gConnect(keys, "key-pressed", data: userData, onKeyPressed)
        gtk_widget_add_controller(gobjectCast(window, to: GtkWidget.self), keys)

        gtk_window_set_child(window, areaWidget)

        // The overlay goes fullscreen on the monitor holding the pointer;
        // its slice of the all-monitors portal image is mapped through the
        // monitors' combined bounding box.
        let pointer = X11Interop.pointerPosition
        fullscreenOnPointerMonitor(window, context: context, pointer: pointer,
                                   imageWidth: imgW, imageHeight: imgH)
        gtk_window_present(window)
        // The WM may withhold focus from a background app's new window
        // (focus-stealing prevention) — force it so Escape works. Deferred:
        // the window must be viewable first (X11Interop.focus is a no-op
        // until then), and mapping completes asynchronously.
        _ = g_timeout_add(80, focusTimeoutCallback, nil)

        current = context
    }

    private static let focusTimeoutCallback: GSourceFunc = { _ in
        if let context = current, !context.finished {
            X11Interop.focus(context.window)
        }
        return 0 // G_SOURCE_REMOVE
    }

    private static func fullscreenOnPointerMonitor(_ window: UnsafeMutablePointer<GtkWindow>,
                                                   context: Context,
                                                   pointer: (x: Double, y: Double)?,
                                                   imageWidth: Double, imageHeight: Double) {
        var chosen: OpaquePointer?
        var chosenRect = GdkRectangle()
        var bounds: GdkRectangle?

        if let display = gdk_display_get_default(),
           let monitors = gdk_display_get_monitors(display) {
            for i in 0..<g_list_model_get_n_items(monitors) {
                guard let item = g_list_model_get_item(monitors, i) else { continue }
                let monitor = OpaquePointer(item)
                var rect = GdkRectangle()
                gdk_monitor_get_geometry(monitor, &rect)

                if var b = bounds {
                    let maxX = max(b.x + b.width, rect.x + rect.width)
                    let maxY = max(b.y + b.height, rect.y + rect.height)
                    b.x = min(b.x, rect.x); b.y = min(b.y, rect.y)
                    b.width = maxX - b.x; b.height = maxY - b.y
                    bounds = b
                } else {
                    bounds = rect
                }

                let containsPointer = pointer.map {
                    Int32($0.x) >= rect.x && Int32($0.x) < rect.x + rect.width &&
                    Int32($0.y) >= rect.y && Int32($0.y) < rect.y + rect.height
                } ?? false
                if chosen == nil || containsPointer {
                    if let chosen { g_object_unref(UnsafeMutableRawPointer(chosen)) }
                    chosen = monitor
                    chosenRect = rect
                } else {
                    g_object_unref(item)
                }
            }
        }

        let b = bounds ?? GdkRectangle(x: 0, y: 0, width: Int32(imageWidth), height: Int32(imageHeight))
        let perGdkX = imageWidth / Double(max(b.width, 1))
        let perGdkY = imageHeight / Double(max(b.height, 1))
        context.subX = Double(chosenRect.x - b.x) * perGdkX
        context.subY = Double(chosenRect.y - b.y) * perGdkY
        context.subW = chosen != nil ? Double(chosenRect.width) * perGdkX : imageWidth
        context.subH = chosen != nil ? Double(chosenRect.height) * perGdkY : imageHeight
        context.monX = Double(chosenRect.x)
        context.monY = Double(chosenRect.y)
        context.monW = Double(max(chosenRect.width, 1))

        if let chosen {
            gtk_window_fullscreen_on_monitor(window, chosen)
            g_object_unref(UnsafeMutableRawPointer(chosen))
        } else {
            gtk_window_fullscreen(window)
        }
    }

    // MARK: - Drawing

    private typealias DrawFn = @convention(c) (
        UnsafeMutablePointer<GtkDrawingArea>?, OpaquePointer?, Int32, Int32, UnsafeMutableRawPointer?
    ) -> Void

    private static let drawFunc: DrawFn = { _, cr, width, height, userData in
        guard let cr, let userData else { return }
        let context = unretained(userData, as: Context.self)

        let w = Double(width), h = Double(height)
        guard w > 0, h > 0 else { return }
        context.widgetW = w
        context.imgPerWidgetX = context.subW / w
        context.imgPerWidgetY = context.subH / h

        // Frozen desktop (this monitor's slice of the portal image).
        paintImage(cr, context, widgetW: w, widgetH: h)

        // Dimmer.
        cairo_set_source_rgba(cr, 0, 0, 0, 0.35)
        cairo_paint(cr)

        guard context.selecting else { return }
        let r = normalizedRect(context.selStart, context.selEnd)
        guard r.w > 0, r.h > 0 else { return }

        // Undimmed selection "hole".
        cairo_save(cr)
        cairo_rectangle(cr, r.x, r.y, r.w, r.h)
        cairo_clip(cr)
        paintImage(cr, context, widgetW: w, widgetH: h)
        cairo_restore(cr)

        // Border.
        cairo_set_source_rgba(cr, 1, 1, 1, 0.9)
        cairo_set_line_width(cr, 1.5)
        cairo_rectangle(cr, r.x + 0.75, r.y + 0.75, r.w - 1.5, r.h - 1.5)
        cairo_stroke(cr)

        // Live size label in image pixels, mirroring the macOS overlay.
        let pxW = Int((r.w * context.imgPerWidgetX).rounded())
        let pxH = Int((r.h * context.imgPerWidgetY).rounded())
        drawSizeLabel(cr, text: "\(pxW) × \(pxH)", selection: r, canvasWidth: w, canvasHeight: h)
    }

    private static func paintImage(_ cr: OpaquePointer, _ context: Context, widgetW: Double, widgetH: Double) {
        cairo_save(cr)
        cairo_scale(cr, widgetW / context.subW, widgetH / context.subH)
        cairo_translate(cr, -context.subX, -context.subY)
        cairo_set_source_surface(cr, context.surface, 0, 0)
        cairo_paint(cr)
        cairo_restore(cr)
    }

    private static func drawSizeLabel(_ cr: OpaquePointer, text: String,
                                      selection r: (x: Double, y: Double, w: Double, h: Double),
                                      canvasWidth: Double, canvasHeight: Double) {
        cairo_select_font_face(cr, "sans-serif", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, 12)
        var extents = cairo_text_extents_t()
        text.withCString { cairo_text_extents(cr, $0, &extents) }

        let padX = 6.0, padY = 4.0
        let boxW = extents.width + padX * 2
        let boxH = extents.height + padY * 2
        // Below the selection's bottom-right corner; flip above if there's no room.
        var lx = min(r.x + r.w - boxW, canvasWidth - boxW - 2)
        lx = max(lx, 2)
        var ly = r.y + r.h + 6
        if ly + boxH > canvasHeight - 2 { ly = max(r.y - boxH - 6, 2) }

        cairo_set_source_rgba(cr, 0, 0, 0, 0.7)
        cairo_rectangle(cr, lx, ly, boxW, boxH)
        cairo_fill(cr)
        cairo_set_source_rgb(cr, 1, 1, 1)
        cairo_move_to(cr, lx + padX - extents.x_bearing, ly + padY - extents.y_bearing)
        text.withCString { cairo_show_text(cr, $0) }
    }

    private static func normalizedRect(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double))
        -> (x: Double, y: Double, w: Double, h: Double) {
        (x: min(a.x, b.x), y: min(a.y, b.y), w: abs(b.x - a.x), h: abs(b.y - a.y))
    }

    // MARK: - Input

    private typealias DragHandler = @convention(c) (UnsafeMutableRawPointer?, Double, Double, UnsafeMutableRawPointer?) -> Void
    private typealias ClickHandler = @convention(c) (OpaquePointer?, Int32, Double, Double, UnsafeMutableRawPointer?) -> Void
    private typealias KeyHandler = @convention(c) (OpaquePointer?, CUnsignedInt, CUnsignedInt, CUnsignedInt, UnsafeMutableRawPointer?) -> gboolean

    private static let onDragBegin: DragHandler = { _, startX, startY, userData in
        guard let userData else { return }
        let context = unretained(userData, as: Context.self)
        context.selecting = true
        context.selStart = (startX, startY)
        context.selEnd = (startX, startY)
        gtk_widget_queue_draw(context.areaWidget)
    }

    private static let onDragUpdate: DragHandler = { _, offsetX, offsetY, userData in
        guard let userData else { return }
        let context = unretained(userData, as: Context.self)
        guard context.selecting else { return }
        context.selEnd = (context.selStart.x + offsetX, context.selStart.y + offsetY)
        gtk_widget_queue_draw(context.areaWidget)
    }

    private static let onDragEnd: DragHandler = { _, offsetX, offsetY, userData in
        guard let userData else { return }
        let context = unretained(userData, as: Context.self)
        guard context.selecting else { return }
        context.selEnd = (context.selStart.x + offsetX, context.selStart.y + offsetY)
        let r = normalizedRect(context.selStart, context.selEnd)
        if r.w >= 4, r.h >= 4 {
            finish(context, croppedPath: crop(context, selection: r))
        } else {
            // A stray click — keep the overlay up, like the macOS dimmer.
            context.selecting = false
            gtk_widget_queue_draw(context.areaWidget)
        }
    }

    private static let onRightClick: ClickHandler = { _, _, _, _, userData in
        guard let userData else { return }
        finish(unretained(userData, as: Context.self), croppedPath: nil)
    }

    private static let onKeyPressed: KeyHandler = { _, keyval, _, _, userData in
        guard let userData, keyval == 0xff1b /* GDK_KEY_Escape */ else { return 0 }
        finish(unretained(userData, as: Context.self), croppedPath: nil)
        return 1
    }

    // MARK: - Completion

    /// Crops the selection out of the full-screen surface at native image
    /// resolution and writes it to a session-temp PNG.
    private static func crop(_ context: Context, selection r: (x: Double, y: Double, w: Double, h: Double)) -> String? {
        let px = Int32((context.subX + r.x * context.imgPerWidgetX).rounded())
        let py = Int32((context.subY + r.y * context.imgPerWidgetY).rounded())
        let pw = max(Int32((r.w * context.imgPerWidgetX).rounded()), 1)
        let ph = max(Int32((r.h * context.imgPerWidgetY).rounded()), 1)

        guard let out = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, pw, ph) else { return nil }
        defer { cairo_surface_destroy(out) }
        guard let cr = cairo_create(out) else { return nil }
        cairo_set_source_surface(cr, context.surface, Double(-px), Double(-py))
        cairo_paint(cr)
        cairo_destroy(cr)

        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("snapfloat-capture-\(UUID().uuidString).png")
        let status = path.withCString { cairo_surface_write_to_png(out, $0) }
        guard status == CAIRO_STATUS_SUCCESS else {
            NSLog("SnapFloat: writing cropped capture failed (cairo status \(status))")
            return nil
        }
        return path
    }

    private static func finish(_ context: Context, croppedPath: String?) {
        guard !context.finished else { return }
        context.finished = true
        let onDone = context.onDone!
        // Selection end mapped into GDK root coords, for preview placement.
        let scale = context.monW / max(context.widgetW, 1)
        let endPoint = croppedPath != nil
            ? (x: context.monX + context.selEnd.x * scale, y: context.monY + context.selEnd.y * scale)
            : nil
        gtk_window_destroy(context.window)
        onDone(croppedPath, endPoint)
    }

    // MARK: - Lifecycle

    private static let onWindowDestroy: GSimpleHandler = { _, userData in
        current = nil
        guard let userData else { return }
        let context = takeRetained(userData, as: Context.self)
        context.finished = true
        cairo_surface_destroy(context.surface)
    }
}
