// Pulls in the full GTK4 / GIO C API. Swift's Clang importer exposes every
// function, struct and enum declared here directly as Swift symbols — no
// binding generator needed. See Sources/SnapFloatLinux/GtkInterop.swift for
// the thin Swift-friendly wrappers built on top of this.
#include <gtk/gtk.h>
#include <gio/gio.h>

// X11/XWayland escape hatch: GNOME's Mutter gives Wayland clients no way to
// position their own windows (no wlr-layer-shell; move requests ignored),
// but override-redirect X11 windows place themselves absolutely — that's how
// menus work. The app therefore prefers the X11 backend (see main.swift) and
// uses a little Xlib for the pinned preview + capture overlay (X11Interop.swift).
#include <gdk/x11/gdkx.h>
#include <X11/Xlib.h>

// Note: GLib/GIO types like GVariant/GDBusConnection import into Swift as
// bare `OpaquePointer` rather than `UnsafeMutablePointer<GVariant>` the way
// GTK's own types (GtkWidget, GtkApplication, ...) do — Swift's ClangImporter
// doesn't surface a named Swift type for them here. Code in SnapFloatLinux
// uses OpaquePointer for anything in the GVariant/GDBus family accordingly.
