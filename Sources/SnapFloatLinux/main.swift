import CGtk4Shim

// GNOME associates windows with the .desktop entry (name + icon in the
// dock/Alt-Tab) by matching WM_CLASS against the desktop-file basename, and
// GTK derives WM_CLASS from the program name — which defaults to the binary
// ("snapfloat-linux") and would leave the windows icon-less. Plain process
// state, so this is set before anything else initializes.
g_set_prgname("com.snapfloat.SnapFloat")

// A plain GApplication, not GtkApplication: at rest this is a tray-only
// app, and the tray, global shortcut, screenshot portal and notifications
// are all GLib/GIO — none of them need GTK. GTK/GDK (and the display
// connection they open) are only initialized lazily, the first time a
// window is actually needed — see GtkLazyInit.swift. This keeps the
// resting process to just GLib + GIO.
let app = g_application_new("com.snapfloat.SnapFloat", GApplicationFlags(rawValue: 0))!

// Held for the app's lifetime — nothing else keeps AppController alive
// (its own closures only capture `self` weakly).
var controller: AppController?

let onActivate: GSimpleHandler = { appPtr, _ in
    guard let appPtr else { return }
    let app = appPtr.assumingMemoryBound(to: GApplication.self)
    LinuxNotifications.configure(app: app)
    controller = AppController(app: app)
    controller?.start()
}
gConnect(app, "activate", onActivate)

let status = g_application_run(app, 0, nil)
exit(status)
