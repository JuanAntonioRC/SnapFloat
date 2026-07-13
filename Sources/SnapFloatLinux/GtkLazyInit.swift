import CGtk4Shim

/// Defers GTK/GDK initialization until the first window is actually needed.
///
/// At rest, SnapFloat is a tray-only app: the tray (hand-rolled
/// StatusNotifierItem D-Bus), the global shortcut (portal D-Bus), the
/// screenshot portal call, and GNotification are all GLib/GIO and never
/// touch gtk_*/gdk_* — see main.swift, which now runs a plain GApplication
/// rather than GtkApplication. Calling gtk_init() opens a display connection
/// and spins up GTK's render pipeline, which is most of the resting memory
/// cost this exists to avoid, so it's held off until the moment some code
/// actually needs to create a window or touch the GDK clipboard/display.
///
/// Call `ensureGtkInitialized()` first thing in every entry point that does:
/// CaptureOverlay.show, PreviewWindow.show, SettingsWindow.show,
/// AnnotationWindow.show, GrantAccessWindow.show, and
/// AppController.handleCapturedImage (whose auto-copy action touches the
/// GDK clipboard before any window of ours necessarily exists, e.g. on the
/// system-picker capture path).
enum GtkLazyInit {
    private static var initialized = false

    static func ensureGtkInitialized() {
        guard !initialized else { return }
        initialized = true

        // Prefer X11 (= XWayland under GNOME, started on demand): Mutter
        // gives Wayland clients no way to pin the floating preview to a
        // corner, but override-redirect X11 windows can place themselves
        // absolutely — see X11Interop.swift. Must be set before GDK opens a
        // display, i.e. before gtk_init().
        gdk_set_allowed_backends("x11,*")
        gtk_init()

        // Themed window icon (X11 _NET_WM_ICON) for WMs that don't do
        // desktop-file matching. Only meaningful once GTK owns a display.
        gtk_window_set_default_icon_name("com.snapfloat.SnapFloat")
    }
}
