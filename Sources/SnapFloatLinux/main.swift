import CGtk4Shim

// Prefer X11 (= XWayland under GNOME, started on demand): Mutter gives
// Wayland clients no way to pin the floating preview to a corner, but
// override-redirect X11 windows can place themselves absolutely — see
// X11Interop.swift. Screen capture, tray and shortcuts are all D-Bus and
// don't care about the backend. Falls back to Wayland if X11 is missing.
gdk_set_allowed_backends("x11,*")

let app = gtk_application_new("com.snapfloat.SnapFloat", GApplicationFlags(rawValue: 0))!

// Held for the app's lifetime — nothing else keeps AppController alive
// (its own closures only capture `self` weakly).
var controller: AppController?

let onActivate: GSimpleHandler = { appPtr, _ in
    guard let appPtr else { return }
    let app = appPtr.assumingMemoryBound(to: GtkApplication.self)
    LinuxNotifications.configure(app: app)
    controller = AppController(app: app)
    controller?.start()
}
gConnect(app, "activate", onActivate)

let gApp = gobjectCast(app, to: GApplication.self)
let status = g_application_run(gApp, 0, nil)
exit(status)
