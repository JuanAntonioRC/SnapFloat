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

// g_unix_fd_add: pumps a raw Xlib connection's events through the GLib main
// loop — used by GlobalHotkey.swift's XGrabKey-based shortcut, which keeps
// its own Display independent of GDK's so the shortcut is live even before
// GTK/GDK are lazily initialized (see GtkLazyInit.swift).
#include <glib-unix.h>

// GNU extension (glibc's <malloc.h>, not declared by <stdlib.h>) exposing
// malloc_trim(3) — used to hand freed heap pages (the capture overlay's
// full-screen scratch buffers, in particular) back to the kernel once a
// window closes. glibc's malloc arenas keep them mapped for reuse otherwise.
#include <malloc.h>

// Note: GLib/GIO types like GVariant/GDBusConnection import into Swift as
// bare `OpaquePointer` rather than `UnsafeMutablePointer<GVariant>` the way
// GTK's own types (GtkWidget, GtkApplication, ...) do — Swift's ClangImporter
// doesn't surface a named Swift type for them here. Code in SnapFloatLinux
// uses OpaquePointer for anything in the GVariant/GDBus family accordingly.
