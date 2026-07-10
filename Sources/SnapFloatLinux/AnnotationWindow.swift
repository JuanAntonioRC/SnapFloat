import CGtk4Shim
import SnapFloatCore
import Glibc
import Foundation

/// Drawing tools, mirroring SnapFloat/AnnotationWindowController.swift's
/// AnnotationTool on macOS.
enum AnnoTool: Int, CaseIterable {
    case pen, line, arrow, rect, oval, text

    var label: String {
        switch self {
        case .pen: return "Pen"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .rect: return "Rect"
        case .oval: return "Oval"
        case .text: return "Text"
        }
    }
}

/// A single annotation, in full-resolution image coordinates — the drawing
/// area maps to/from them through the current aspect-fit scale, which lets
/// the window be freely resized (like macOS's resizable editor). Mirrors
/// macOS's `Annotation` struct.
private struct AnnoShape {
    var tool: AnnoTool
    var color: (r: Double, g: Double, b: Double)
    var lineWidth: Double                 // image-space
    var points: [(x: Double, y: Double)]  // image-space
    var text: String?
    var fontSize: Double = 0              // image-space, text tool only
}

/// Annotation editor: draw over the captured screenshot with a
/// GtkDrawingArea + Cairo canvas, mirroring SnapFloat/AnnotationWindowController.swift.
/// Opened by clicking the PreviewWindow thumbnail.
enum AnnotationWindow {

    private static let palette: [(name: String, r: Double, g: Double, b: Double)] = [
        ("red",    0.918, 0.231, 0.188),
        ("orange", 1.0,   0.584, 0.0),
        ("yellow", 1.0,   0.8,   0.0),
        ("green",  0.204, 0.780, 0.349),
        ("blue",   0.0,   0.478, 1.0),
        ("white",  1.0,   1.0,   1.0),
        ("black",  0.0,   0.0,   0.0),
    ]

    private final class Context {
        var window: UnsafeMutablePointer<GtkWindow>!
        var drawingAreaWidget: UnsafeMutablePointer<GtkWidget>!
        var baseSurface: OpaquePointer!
        var imageWidth: Double = 0
        var imageHeight: Double = 0
        // Current aspect-fit mapping from image space into the drawing area
        // (letterbox offsets in widget coords) — recomputed on every draw,
        // since the window is resizable.
        var scale: Double = 1
        var offsetX: Double = 0
        var offsetY: Double = 0

        var shapes: [AnnoShape] = []
        var activeShape: AnnoShape?
        var dragStart: (x: Double, y: Double) = (0, 0)

        var currentTool: AnnoTool = .pen
        var currentColor: (r: Double, g: Double, b: Double) = (AnnotationWindow.palette[0].r, AnnotationWindow.palette[0].g, AnnotationWindow.palette[0].b)
        var currentLineWidth: Double = 3

        var overlayWidget: UnsafeMutablePointer<GtkWidget>!
        var textEntry: UnsafeMutablePointer<GtkWidget>?
        var textOrigin: (x: Double, y: Double)?  // image-space
        var textFontSize: Double = 0             // image-space

        var toggleButtons: [UnsafeMutablePointer<GtkToggleButton>] = []
        var colorButtons: [UnsafeMutablePointer<GtkToggleButton>] = []

        var app: UnsafeMutablePointer<GtkApplication>!
    }

    private static var current: Context?
    private static var cssLoaded = false

    // MARK: - Public

    static func show(imagePath: String, app: UnsafeMutablePointer<GtkApplication>) {
        if let current { gtk_window_destroy(current.window) }
        ensureCssLoaded()

        guard let surface = imagePath.withCString({ cairo_image_surface_create_from_png($0) }) else { return }
        let imgW = Double(cairo_image_surface_get_width(surface))
        let imgH = Double(cairo_image_surface_get_height(surface))
        guard imgW > 0, imgH > 0 else {
            cairo_surface_destroy(surface)
            NSLog("SnapFloat: annotation editor could not load \(imagePath)")
            return
        }

        let context = Context()
        context.baseSurface = surface
        context.imageWidth = imgW
        context.imageHeight = imgH
        context.app = app

        // Initial window size: image at 1:1 up to 1000×700. Just a starting
        // point — the canvas re-fits on every draw as the window resizes.
        let maxW = 1000.0, maxH = 700.0
        let initialScale = min(min(maxW / imgW, maxH / imgH), 1.0)
        context.scale = initialScale

        let window = gobjectCast(gtk_window_new(), to: GtkWindow.self)
        gtk_window_set_title(window, "SnapFloat — Annotate")
        context.window = window

        let root = gobjectCast(gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!, to: GtkBox.self)

        let userData = retainedPointer(context)
        gConnect(window, "destroy", data: userData, onWindowDestroy)

        gtk_box_append(root, buildToolbar(context: context, userData: userData))

        // Canvas (in a GtkOverlay so the text-tool entry can float on top).
        // Expands with the window; the image is aspect-fit inside it.
        let areaWidget = gtk_drawing_area_new()!
        gtk_widget_set_size_request(areaWidget, 320, 200)
        gtk_widget_set_hexpand(areaWidget, 1)
        gtk_widget_set_vexpand(areaWidget, 1)
        context.drawingAreaWidget = areaWidget

        let area = gobjectCast(areaWidget, to: GtkDrawingArea.self)
        gtk_drawing_area_set_draw_func(area, drawFunc, userData, nil)

        let drag = gtk_gesture_drag_new()!
        gConnect(drag, "drag-begin", data: userData, onDragBegin)
        gConnect(drag, "drag-update", data: userData, onDragUpdate)
        gConnect(drag, "drag-end", data: userData, onDragEnd)
        gtk_widget_add_controller(areaWidget, drag)

        let overlay = gtk_overlay_new()!
        gtk_overlay_set_child(OpaquePointer(overlay), areaWidget)
        context.overlayWidget = overlay
        gtk_widget_set_vexpand(overlay, 1)
        gtk_box_append(root, overlay)

        gtk_window_set_child(window, gobjectCast(root, to: GtkWidget.self))
        // ~52px accounts for the toolbar row; only affects the initial size.
        gtk_window_set_default_size(window, Int32(imgW * initialScale), Int32(imgH * initialScale + 52))
        gtk_window_present(window)
        current = context
    }

    private static func ensureCssLoaded() {
        guard !cssLoaded else { return }
        cssLoaded = true
        let provider = gtk_css_provider_new()!
        var css = ".snapfloat-swatch { min-width: 22px; min-height: 22px; border-radius: 5px; padding: 0; }\n"
        for entry in palette {
            let hex = String(format: "#%02x%02x%02x", Int(entry.r * 255), Int(entry.g * 255), Int(entry.b * 255))
            css += ".snapfloat-swatch-\(entry.name) { background-color: \(hex); }\n"
        }
        css.withCString { gtk_css_provider_load_from_string(provider, $0) }
        if let display = gdk_display_get_default() {
            gtk_style_context_add_provider_for_display(display, OpaquePointer(provider), UInt32(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION))
        }
    }

    // MARK: - Toolbar

    private static func buildToolbar(context: Context, userData: UnsafeMutableRawPointer) -> UnsafeMutablePointer<GtkWidget> {
        let bar = gobjectCast(gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!, to: GtkBox.self)
        gtk_widget_set_margin_start(gobjectCast(bar, to: GtkWidget.self), 8)
        gtk_widget_set_margin_end(gobjectCast(bar, to: GtkWidget.self), 8)
        gtk_widget_set_margin_top(gobjectCast(bar, to: GtkWidget.self), 6)
        gtk_widget_set_margin_bottom(gobjectCast(bar, to: GtkWidget.self), 6)

        // Tools
        var firstTool: UnsafeMutablePointer<GtkToggleButton>?
        for tool in AnnoTool.allCases {
            let btn = gobjectCast(gtk_toggle_button_new_with_label(tool.label)!, to: GtkToggleButton.self)
            if let firstTool { gtk_toggle_button_set_group(btn, firstTool) } else { firstTool = btn }
            if tool == .pen { gtk_toggle_button_set_active(btn, 1) }
            gConnect(btn, "toggled", data: userData, onToolToggled)
            gtk_box_append(bar, gobjectCast(btn, to: GtkWidget.self))
            context.toggleButtons.append(btn)
        }

        gtk_box_append(bar, gobjectCast(gtk_separator_new(GTK_ORIENTATION_VERTICAL)!, to: GtkWidget.self))

        // Width
        let widthScale = gobjectCast(gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 1, 12, 1)!, to: GtkRange.self)
        gtk_range_set_value(widthScale, context.currentLineWidth)
        gtk_widget_set_size_request(gobjectCast(widthScale, to: GtkWidget.self), 90, -1)
        gConnect(widthScale, "value-changed", data: userData, onWidthChanged)
        gtk_box_append(bar, gobjectCast(widthScale, to: GtkWidget.self))

        gtk_box_append(bar, gobjectCast(gtk_separator_new(GTK_ORIENTATION_VERTICAL)!, to: GtkWidget.self))

        // Colors
        var firstColor: UnsafeMutablePointer<GtkToggleButton>?
        for (index, entry) in palette.enumerated() {
            let btn = gobjectCast(gtk_toggle_button_new()!, to: GtkToggleButton.self)
            gtk_widget_add_css_class(gobjectCast(btn, to: GtkWidget.self), "snapfloat-swatch")
            gtk_widget_add_css_class(gobjectCast(btn, to: GtkWidget.self), "snapfloat-swatch-\(entry.name)")
            if let firstColor { gtk_toggle_button_set_group(btn, firstColor) } else { firstColor = btn }
            if index == 0 { gtk_toggle_button_set_active(btn, 1) }
            gConnect(btn, "toggled", data: userData, onColorToggled)
            gtk_box_append(bar, gobjectCast(btn, to: GtkWidget.self))
            context.colorButtons.append(btn)
        }

        // Spacer
        let spacer = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
        gtk_widget_set_hexpand(spacer, 1)
        gtk_box_append(bar, spacer)

        // Actions
        let undoBtn = gtk_button_new_with_label("Undo")!
        gConnect(undoBtn, "clicked", data: userData, onUndoClicked)
        gtk_box_append(bar, undoBtn)

        let copyBtn = gtk_button_new_with_label("Copy")!
        gConnect(copyBtn, "clicked", data: userData, onCopyClicked)
        gtk_box_append(bar, copyBtn)

        let saveBtn = gtk_button_new_with_label("Save")!
        gConnect(saveBtn, "clicked", data: userData, onSaveClicked)
        gtk_box_append(bar, saveBtn)

        return gobjectCast(bar, to: GtkWidget.self)
    }

    // MARK: - Drawing

    private typealias DrawFn = @convention(c) (
        UnsafeMutablePointer<GtkDrawingArea>?, OpaquePointer?, Int32, Int32, UnsafeMutableRawPointer?
    ) -> Void

    private static let drawFunc: DrawFn = { _, cr, width, height, userData in
        guard let cr, let userData else { return }
        let context = unretained(userData, as: Context.self)

        // Re-fit the image into the current allocation (letterboxed,
        // centered) and remember the mapping for the gesture handlers.
        let w = Double(width), h = Double(height)
        let scale = min(w / context.imageWidth, h / context.imageHeight)
        context.scale = scale
        context.offsetX = (w - context.imageWidth * scale) / 2
        context.offsetY = (h - context.imageHeight * scale) / 2

        cairo_save(cr)
        cairo_translate(cr, context.offsetX, context.offsetY)
        cairo_scale(cr, scale, scale)
        cairo_rectangle(cr, 0, 0, context.imageWidth, context.imageHeight)
        cairo_clip(cr)
        cairo_set_source_surface(cr, context.baseSurface, 0, 0)
        cairo_paint(cr)

        // Shapes are in image coordinates — painted under the same transform.
        for shape in context.shapes { paint(shape, cr: cr) }
        if let active = context.activeShape { paint(active, cr: cr) }
        cairo_restore(cr)
    }

    private static func paint(_ shape: AnnoShape, cr: OpaquePointer) {
        guard !shape.points.isEmpty else { return }
        cairo_set_source_rgb(cr, shape.color.r, shape.color.g, shape.color.b)
        cairo_set_line_width(cr, shape.lineWidth)
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
        cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)

        switch shape.tool {
        case .pen:
            if shape.points.count == 1 {
                let p = shape.points[0]
                cairo_arc(cr, p.x, p.y, shape.lineWidth / 2, 0, 2 * .pi)
                cairo_fill(cr)
                return
            }
            cairo_move_to(cr, shape.points[0].x, shape.points[0].y)
            for p in shape.points.dropFirst() { cairo_line_to(cr, p.x, p.y) }
            cairo_stroke(cr)

        case .line:
            guard shape.points.count >= 2 else { return }
            cairo_move_to(cr, shape.points[0].x, shape.points[0].y)
            cairo_line_to(cr, shape.points[1].x, shape.points[1].y)
            cairo_stroke(cr)

        case .arrow:
            guard shape.points.count >= 2 else { return }
            paintArrow(cr, from: shape.points[0], to: shape.points[1], lineWidth: shape.lineWidth)

        case .rect:
            guard shape.points.count >= 2 else { return }
            let r = normalizedRect(shape.points[0], shape.points[1])
            cairo_rectangle(cr, r.x, r.y, r.w, r.h)
            cairo_stroke(cr)

        case .oval:
            guard shape.points.count >= 2 else { return }
            let r = normalizedRect(shape.points[0], shape.points[1])
            cairo_save(cr)
            cairo_translate(cr, r.x + r.w / 2, r.y + r.h / 2)
            cairo_scale(cr, max(r.w / 2, 0.01), max(r.h / 2, 0.01))
            cairo_arc(cr, 0, 0, 1, 0, 2 * .pi)
            cairo_restore(cr)
            cairo_stroke(cr)

        case .text:
            guard let text = shape.text, !text.isEmpty else { return }
            let fontSize = shape.fontSize > 0 ? shape.fontSize : max(shape.lineWidth * 5, 14)
            cairo_select_font_face(cr, "sans-serif", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
            cairo_set_font_size(cr, fontSize)
            cairo_move_to(cr, shape.points[0].x, shape.points[0].y + fontSize)
            text.withCString { cairo_show_text(cr, $0) }
        }
    }

    private static func paintArrow(_ cr: OpaquePointer, from: (x: Double, y: Double), to: (x: Double, y: Double), lineWidth: Double) {
        let headLength = max(lineWidth * 4, 14)
        let angle = atan2(to.y - from.y, to.x - from.x)
        let headAngle = Double.pi / 6

        let p1 = (x: to.x - headLength * cos(angle - headAngle), y: to.y - headLength * sin(angle - headAngle))
        let p2 = (x: to.x - headLength * cos(angle + headAngle), y: to.y - headLength * sin(angle + headAngle))
        let base = (x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)

        cairo_move_to(cr, from.x, from.y)
        cairo_line_to(cr, base.x, base.y)
        cairo_stroke(cr)

        cairo_move_to(cr, to.x, to.y)
        cairo_line_to(cr, p1.x, p1.y)
        cairo_line_to(cr, p2.x, p2.y)
        cairo_close_path(cr)
        cairo_fill(cr)
    }

    private static func normalizedRect(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> (x: Double, y: Double, w: Double, h: Double) {
        (x: min(a.x, b.x), y: min(a.y, b.y), w: abs(b.x - a.x), h: abs(b.y - a.y))
    }

    // MARK: - Gesture handlers

    private typealias DragHandler = @convention(c) (UnsafeMutableRawPointer?, Double, Double, UnsafeMutableRawPointer?) -> Void

    /// Maps a drawing-area point into image coordinates, clamped to the image.
    private static func toImagePoint(_ context: Context, _ x: Double, _ y: Double) -> (x: Double, y: Double) {
        let scale = max(context.scale, 0.0001)
        return (min(max((x - context.offsetX) / scale, 0), context.imageWidth),
                min(max((y - context.offsetY) / scale, 0), context.imageHeight))
    }

    private static let onDragBegin: DragHandler = { gesturePtr, startX, startY, userData in
        guard let userData else { return }
        let context = unretained(userData, as: Context.self)
        commitPendingText(context)

        if context.currentTool == .text {
            showTextEntry(context: context, at: (startX, startY))
            return
        }

        // dragStart stays in widget coords (GTK reports updates as offsets
        // from it); shape points are converted to image coords on the spot.
        context.dragStart = (startX, startY)
        context.activeShape = AnnoShape(tool: context.currentTool, color: context.currentColor,
                                        lineWidth: context.currentLineWidth / max(context.scale, 0.0001),
                                        points: [toImagePoint(context, startX, startY)], text: nil)
    }

    private static let onDragUpdate: DragHandler = { _, offsetX, offsetY, userData in
        guard let userData, let context = optionalContext(userData), context.activeShape != nil else { return }
        let pt = toImagePoint(context, context.dragStart.x + offsetX, context.dragStart.y + offsetY)
        switch context.activeShape!.tool {
        case .pen:
            context.activeShape!.points.append(pt)
        case .line, .arrow, .rect, .oval:
            if context.activeShape!.points.count < 2 { context.activeShape!.points.append(pt) }
            else { context.activeShape!.points[1] = pt }
        case .text:
            break
        }
        gtk_widget_queue_draw(context.drawingAreaWidget)
    }

    private static let onDragEnd: DragHandler = { _, offsetX, offsetY, userData in
        guard let userData else { return }
        let context = unretained(userData, as: Context.self)
        if var active = context.activeShape, active.tool != .text {
            let pt = toImagePoint(context, context.dragStart.x + offsetX, context.dragStart.y + offsetY)
            switch active.tool {
            case .pen: active.points.append(pt)
            case .line, .arrow, .rect, .oval:
                if active.points.count < 2 { active.points.append(pt) } else { active.points[1] = pt }
            case .text: break
            }
            context.shapes.append(active)
        }
        context.activeShape = nil
        gtk_widget_queue_draw(context.drawingAreaWidget)
    }

    private static func optionalContext(_ ptr: UnsafeMutableRawPointer) -> Context? {
        unretained(ptr, as: Context.self)
    }

    // MARK: - Text tool

    private static func showTextEntry(context: Context, at point: (x: Double, y: Double)) {
        let entry = gtk_entry_new()!
        gtk_widget_set_halign(entry, GTK_ALIGN_START)
        gtk_widget_set_valign(entry, GTK_ALIGN_START)
        gtk_widget_set_margin_start(entry, Int32(point.x))
        gtk_widget_set_margin_top(entry, Int32(point.y))
        gtk_widget_set_size_request(entry, 160, -1)

        // Unretained: `context` is already kept alive for the window's whole
        // lifetime by the retain in show()/onWindowDestroy — no separate
        // retain/release pair needed here (and taking one would leak if the
        // window closes while an entry is open without Enter being pressed).
        gConnect(entry, "activate", data: unretainedPointer(context), onTextEntryActivate)

        gtk_overlay_add_overlay(OpaquePointer(context.overlayWidget), entry)
        gtk_widget_grab_focus(entry)

        context.textEntry = entry
        context.textOrigin = toImagePoint(context, point.x, point.y)
        context.textFontSize = max(context.currentLineWidth * 5, 14) / max(context.scale, 0.0001)
    }

    private static let onTextEntryActivate: GSimpleHandler = { _, userData in
        guard let userData else { return }
        commitPendingText(unretained(userData, as: Context.self))
    }

    private static func commitPendingText(_ context: Context) {
        guard let entry = context.textEntry, let origin = context.textOrigin else { return }
        let text = String(cString: gtk_editable_get_text(OpaquePointer(entry)))
        gtk_overlay_remove_overlay(OpaquePointer(context.overlayWidget), entry)
        context.textEntry = nil
        context.textOrigin = nil

        if !text.isEmpty {
            context.shapes.append(AnnoShape(tool: .text, color: context.currentColor,
                                            lineWidth: context.currentLineWidth, points: [origin], text: text,
                                            fontSize: context.textFontSize))
        }
        gtk_widget_queue_draw(context.drawingAreaWidget)
    }

    // MARK: - Toolbar handlers

    private static let onToolToggled: GSimpleHandler = { widgetPtr, userData in
        guard let widgetPtr, let userData else { return }
        let btn = widgetPtr.assumingMemoryBound(to: GtkToggleButton.self)
        guard gtk_toggle_button_get_active(btn) != 0 else { return }
        let context = unretained(userData, as: Context.self)
        if let index = context.toggleButtons.firstIndex(where: { $0 == btn }) {
            context.currentTool = AnnoTool.allCases[index]
        }
    }

    private static let onColorToggled: GSimpleHandler = { widgetPtr, userData in
        guard let widgetPtr, let userData else { return }
        let btn = widgetPtr.assumingMemoryBound(to: GtkToggleButton.self)
        guard gtk_toggle_button_get_active(btn) != 0 else { return }
        let context = unretained(userData, as: Context.self)
        if let index = context.colorButtons.firstIndex(where: { $0 == btn }) {
            let entry = palette[index]
            context.currentColor = (entry.r, entry.g, entry.b)
        }
    }

    private static let onWidthChanged: GSimpleHandler = { widgetPtr, userData in
        guard let widgetPtr, let userData else { return }
        let range = widgetPtr.assumingMemoryBound(to: GtkRange.self)
        let context = unretained(userData, as: Context.self)
        context.currentLineWidth = gtk_range_get_value(range)
    }

    private static let onUndoClicked: GSimpleHandler = { _, userData in
        guard let userData else { return }
        let context = unretained(userData, as: Context.self)
        commitPendingText(context)
        guard !context.shapes.isEmpty else { return }
        context.shapes.removeLast()
        gtk_widget_queue_draw(context.drawingAreaWidget)
    }

    private static let onCopyClicked: GSimpleHandler = { _, userData in
        guard let userData else { return }
        let context = unretained(userData, as: Context.self)
        commitPendingText(context)
        guard let composite = composite(context) else { return }
        let tmpPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("snapfloat-annotate-\(UUID().uuidString).png")
        tmpPath.withCString { _ = cairo_surface_write_to_png(composite, $0) }
        cairo_surface_destroy(composite)
        CaptureActions.copyToClipboard(imagePath: tmpPath)
        try? FileManager.default.removeItem(atPath: tmpPath)
        gtk_window_destroy(context.window)
    }

    private static let onSaveClicked: GSimpleHandler = { _, userData in
        guard let userData else { return }
        let context = unretained(userData, as: Context.self)
        commitPendingText(context)

        guard let dir = AppSettingsStore.shared.saveDirectoryPath else {
            SettingsWindow.show(app: context.app)
            return
        }
        guard let composite = composite(context) else { return }
        let destination = (dir as NSString).appendingPathComponent(ScreenshotFileNamer.makeFilename())
        destination.withCString { _ = cairo_surface_write_to_png(composite, $0) }
        cairo_surface_destroy(composite)
        LinuxNotifications.postSaveNotification(path: destination)
        gtk_window_destroy(context.window)
    }

    /// Renders the base image + all committed shapes at full image
    /// resolution — shapes are already stored in image coordinates, so
    /// they paint 1:1 (macOS's compositeAnnotation scales up instead).
    private static func composite(_ context: Context) -> OpaquePointer? {
        guard let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, Int32(context.imageWidth), Int32(context.imageHeight)) else {
            return nil
        }
        guard let cr = cairo_create(surface) else { cairo_surface_destroy(surface); return nil }

        cairo_set_source_surface(cr, context.baseSurface, 0, 0)
        cairo_paint(cr)

        for shape in context.shapes { paint(shape, cr: cr) }

        cairo_destroy(cr)
        return surface
    }

    // MARK: - Lifecycle

    private static let onWindowDestroy: GSimpleHandler = { _, userData in
        current = nil
        guard let userData else { return }
        let context = takeRetained(userData, as: Context.self)
        cairo_surface_destroy(context.baseSurface)
    }
}
