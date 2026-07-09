import CGtk4Shim

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
