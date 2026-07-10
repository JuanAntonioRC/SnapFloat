import CGtk4Shim
import Foundation

/// Small Xlib/EWMH helpers for the things Wayland refuses to let apps do:
/// absolute window positioning, keep-above, and not stealing focus.
///
/// Mutter ignores position requests from regular clients on both Wayland
/// (no wlr-layer-shell) and XWayland (XMoveWindow / initial geometry are
/// overridden), and pointer input never reaches override-redirect windows
/// of background apps — all verified empirically. What *does* work is the
/// EWMH pager protocol: a `_NET_MOVERESIZE_WINDOW` client message moves a
/// managed window exactly, `_NET_WM_STATE_ABOVE` floats it, and a zero
/// `_NET_WM_USER_TIME` maps it without taking keyboard focus — together
/// the closest Linux equivalent of macOS's non-activating floating NSPanel.
///
/// main.swift therefore prefers the X11 backend (GNOME starts XWayland on
/// demand). Every helper here degrades to a no-op on a pure-Wayland display.
enum X11Interop {

    /// True when the default GdkDisplay is backed by X11/XWayland.
    static var isX11: Bool {
        guard let display = gdk_display_get_default() else { return false }
        let instance = UnsafeMutableRawPointer(display).assumingMemoryBound(to: GTypeInstance.self)
        guard let name = g_type_name_from_instance(instance) else { return false }
        return String(cString: name).contains("X11")
    }

    /// Current pointer position in GDK logical coordinates. X reports the
    /// pointer in physical root pixels, so the position is divided by the
    /// global window-scale factor (2 on HiDPI) to be comparable with GDK
    /// monitor geometry.
    static var pointerPosition: (x: Double, y: Double)? {
        guard isX11, let display = gdk_display_get_default(),
              let xdisplay = gdk_x11_display_get_xdisplay(display) else { return nil }
        let root = XDefaultRootWindow(xdisplay)
        var rootRet: Window = 0, childRet: Window = 0
        var rootX: Int32 = 0, rootY: Int32 = 0, winX: Int32 = 0, winY: Int32 = 0
        var mask: UInt32 = 0
        guard XQueryPointer(xdisplay, root, &rootRet, &childRet,
                            &rootX, &rootY, &winX, &winY, &mask) != 0 else { return nil }
        var scale = 1.0
        if let monitors = gdk_display_get_monitors(display),
           g_list_model_get_n_items(monitors) > 0,
           let item = g_list_model_get_item(monitors, 0) {
            scale = Double(max(gdk_monitor_get_scale_factor(OpaquePointer(item)), 1))
            g_object_unref(item)
        }
        return (Double(rootX) / scale, Double(rootY) / scale)
    }

    private static func xids(for window: UnsafeMutablePointer<GtkWindow>) -> (display: OpaquePointer, window: Window)? {
        guard isX11, let display = gdk_display_get_default() else { return nil }
        let widget = gobjectCast(window, to: GtkWidget.self)
        guard let native = gtk_widget_get_native(widget),
              let surface = gtk_native_get_surface(native),
              let xdisplay = gdk_x11_display_get_xdisplay(display) else { return nil }
        return (xdisplay, gdk_x11_surface_get_xid(surface))
    }

    /// Prevents the window manager from focusing the window when it maps
    /// (`_NET_WM_USER_TIME` = 0). Call after realize, before present.
    static func setNoFocusOnMap(_ window: UnsafeMutablePointer<GtkWindow>) {
        guard let xi = xids(for: window) else { return }
        var zero: CUnsignedLong = 0
        let property = XInternAtom(xi.display, "_NET_WM_USER_TIME", 0)
        let cardinal = XInternAtom(xi.display, "CARDINAL", 0)
        withUnsafeBytes(of: &zero) { buf in
            _ = XChangeProperty(xi.display, xi.window, property, cardinal, 32, PropModeReplace,
                                buf.baseAddress!.assumingMemoryBound(to: UInt8.self), 1)
        }
        XFlush(xi.display)
    }

    /// Moves a *managed* window to absolute root coordinates via the EWMH
    /// pager protocol — the one move request Mutter honors. Only works once
    /// the window is mapped.
    static func ewmhMove(_ window: UnsafeMutablePointer<GtkWindow>, x: Int32, y: Int32) {
        // StaticGravity(10): coordinates are the client area's, exact.
        // Bits 8/9: x/y present. Bits 12-15: source = pager(2).
        let flags: CLong = 10 | (1 << 8) | (1 << 9) | (2 << 12)
        sendClientMessage(window, type: "_NET_MOVERESIZE_WINDOW",
                          data: (flags, CLong(x), CLong(y), 0, 0))
    }

    /// Floats the window above normal windows and keeps it out of the
    /// taskbar/Alt-Tab, like macOS's `.floating` panel level.
    static func keepAbove(_ window: UnsafeMutablePointer<GtkWindow>) {
        guard let xi = xids(for: window) else { return }
        let add: CLong = 1, sourcePager: CLong = 2
        let above = CLong(bitPattern: UInt(XInternAtom(xi.display, "_NET_WM_STATE_ABOVE", 0)))
        let skipTaskbar = CLong(bitPattern: UInt(XInternAtom(xi.display, "_NET_WM_STATE_SKIP_TASKBAR", 0)))
        let skipPager = CLong(bitPattern: UInt(XInternAtom(xi.display, "_NET_WM_STATE_SKIP_PAGER", 0)))
        sendClientMessage(window, type: "_NET_WM_STATE", data: (add, above, skipTaskbar, sourcePager, 0))
        sendClientMessage(window, type: "_NET_WM_STATE", data: (add, skipPager, 0, sourcePager, 0))
    }

    /// Forces keyboard focus onto a window the WM didn't focus (e.g. the
    /// capture overlay presented by a background app) so Escape works.
    /// Silently skipped until the window is viewable — XSetInputFocus on an
    /// unmapped window is a fatal BadMatch (GTK's X error handler aborts),
    /// so callers must defer this until after the map (see CaptureOverlay).
    static func focus(_ window: UnsafeMutablePointer<GtkWindow>) {
        guard let xi = xids(for: window) else { return }
        var attrs = XWindowAttributes()
        guard XGetWindowAttributes(xi.display, xi.window, &attrs) != 0,
              attrs.map_state == IsViewable else { return }
        XSetInputFocus(xi.display, xi.window, Int32(RevertToParent), Time(CurrentTime))
        XFlush(xi.display)
    }

    /// XDG-portal parent-window handle for dialogs ("x11:0x<xid>").
    static func portalParentHandle(_ window: UnsafeMutablePointer<GtkWindow>) -> String {
        guard let xi = xids(for: window) else { return "" }
        return String(format: "x11:0x%lx", xi.window)
    }

    private static func sendClientMessage(_ window: UnsafeMutablePointer<GtkWindow>,
                                          type: String,
                                          data: (CLong, CLong, CLong, CLong, CLong)) {
        guard let xi = xids(for: window) else { return }
        var event = XEvent()
        event.xclient.type = ClientMessage
        event.xclient.window = xi.window
        event.xclient.message_type = XInternAtom(xi.display, type, 0)
        event.xclient.format = 32
        event.xclient.data.l = data
        let root = XDefaultRootWindow(xi.display)
        let mask: CLong = CLong(SubstructureRedirectMask) | CLong(SubstructureNotifyMask)
        _ = XSendEvent(xi.display, root, 0, mask, &event)
        XFlush(xi.display)
    }
}
