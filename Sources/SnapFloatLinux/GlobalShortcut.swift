import CGtk4Shim
import Foundation

/// Global keyboard shortcut via org.freedesktop.portal.GlobalShortcuts.
///
/// Unlike macOS's Carbon-based HotkeyManager, the actual key combination
/// isn't chosen in our own UI — GNOME shows its own one-time permission
/// prompt on first bind, and the physical keys are assigned/changed by the
/// user in GNOME's own Settings app (Keyboard → View and Customize
/// Shortcuts → SnapFloat). This mirrors how PortalScreenshot delegates the
/// region picker to GNOME's own UI rather than drawing a custom overlay.
final class GlobalShortcut {

    static let shortcutId = "capture-area"

    private let connection: OpaquePointer
    private let onActivated: () -> Void
    private(set) var triggerDescription: String?
    var onTriggerDescriptionChanged: ((String?) -> Void)?

    private var sessionHandle: String?

    init(connection: OpaquePointer, onActivated: @escaping () -> Void) {
        self.connection = connection
        self.onActivated = onActivated
    }

    func start() {
        createSession()
    }

    // MARK: - CreateSession

    private func createSession() {
        let token = "snapfloat_create\(UInt32.random(in: 0..<UInt32.max))"
        let options = gvDict([
            ("handle_token", gvString(token)),
            ("session_handle_token", gvString("snapfloat_session")),
        ])
        let params = gvTuple([options])

        portalRequest(
            connection: connection,
            interface: "org.freedesktop.portal.GlobalShortcuts",
            method: "CreateSession",
            params: params,
            handleToken: token
        ) { [weak self] responseCode, results in
            guard let self, responseCode == 0,
                  let sessionHandle = gvLookupString(results, "session_handle") else {
                NSLog("SnapFloat: GlobalShortcuts CreateSession failed (code \(responseCode))")
                return
            }
            self.sessionHandle = sessionHandle
            self.bindShortcuts(sessionHandle: sessionHandle)
        }
    }

    // MARK: - BindShortcuts

    private func bindShortcuts(sessionHandle: String) {
        let token = "snapfloat_bind\(UInt32.random(in: 0..<UInt32.max))"
        let shortcutEntry = gvTuple([
            gvString(Self.shortcutId),
            gvDict([
                ("description", gvString("Capture Area")),
                // A hint only — mirrors macOS's ⇧⌘2 default. The portal may
                // ignore it, and the user picks the real keys in GNOME
                // Settings either way.
                ("preferred_trigger", gvString("CTRL+SHIFT+2")),
            ]),
        ])
        let shortcuts = gvArray(type: "a(sa{sv})", [shortcutEntry])
        let options = gvDict([("handle_token", gvString(token))])
        let params = gvTuple([gvObjectPath(sessionHandle), shortcuts, gvString(""), options])

        portalRequest(
            connection: connection,
            interface: "org.freedesktop.portal.GlobalShortcuts",
            method: "BindShortcuts",
            params: params,
            handleToken: token
        ) { [weak self] responseCode, results in
            guard let self, responseCode == 0 else {
                NSLog("SnapFloat: GlobalShortcuts BindShortcuts failed (code \(responseCode))")
                return
            }
            self.updateTriggerDescription(fromResults: results)
            self.subscribeActivated()
            self.subscribeShortcutsChanged()
        }
    }

    private func updateTriggerDescription(fromResults results: OpaquePointer) {
        guard let shortcutsVariant = "shortcuts".withCString({
            g_variant_lookup_value(results, $0, g_variant_type_new("a(sa{sv})"))
        }) else { return }
        defer { g_variant_unref(shortcutsVariant) }
        updateTriggerDescription(fromShortcuts: shortcutsVariant)
    }

    /// - Parameter shortcuts: an `a(sa{sv})` array of (id, properties) pairs,
    ///   as found both in BindShortcuts results and the ShortcutsChanged signal.
    private func updateTriggerDescription(fromShortcuts shortcuts: OpaquePointer) {
        let n = g_variant_n_children(shortcuts)
        for i in 0..<n {
            let entry = g_variant_get_child_value(shortcuts, i)
            defer { g_variant_unref(entry) }
            let idVariant = g_variant_get_child_value(entry, 0)
            let id = String(cString: g_variant_get_string(idVariant, nil))
            g_variant_unref(idVariant)
            guard id == Self.shortcutId else { continue }
            guard let propsVariant = g_variant_get_child_value(entry, 1) else { return }
            defer { g_variant_unref(propsVariant) }
            triggerDescription = gvLookupString(propsVariant, "trigger_description")
            onTriggerDescriptionChanged?(triggerDescription)
            return
        }
    }

    // MARK: - Activated signal

    private typealias ActivatedHandler = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        OpaquePointer?,
        UnsafeMutableRawPointer?
    ) -> Void

    private func subscribeActivated() {
        subscribe(signal: "Activated", handler: Self.onActivatedSignal)
    }

    /// Keeps the displayed key combination current when the user rebinds it
    /// in GNOME Settings while SnapFloat is running.
    private func subscribeShortcutsChanged() {
        subscribe(signal: "ShortcutsChanged", handler: Self.onShortcutsChangedSignal)
    }

    /// App-lifetime subscription — the retain taken here is only released if
    /// the connection goes away (i.e. at exit).
    private func subscribe(signal: String, handler: ActivatedHandler) {
        let userData = retainedPointer(self)
        signal.withCString { sig in
            _ = g_dbus_connection_signal_subscribe(
                connection,
                "org.freedesktop.portal.Desktop",
                "org.freedesktop.portal.GlobalShortcuts",
                sig,
                "/org/freedesktop/portal/desktop",
                nil,
                GDBusSignalFlags(rawValue: 0),
                handler,
                userData,
                { data in
                    guard let data else { return }
                    _ = takeRetained(data, as: GlobalShortcut.self)
                }
            )
        }
    }

    private static let onActivatedSignal: ActivatedHandler = { _, _, _, _, _, parameters, userData in
        guard let userData, let parameters else { return }
        let shortcut = unretained(userData, as: GlobalShortcut.self)

        let idVariant = g_variant_get_child_value(parameters, 1)
        let id = String(cString: g_variant_get_string(idVariant, nil))
        g_variant_unref(idVariant)

        if id == GlobalShortcut.shortcutId {
            shortcut.onActivated()
        }
    }

    // Parameters: (o session_handle, a(sa{sv}) shortcuts)
    private static let onShortcutsChangedSignal: ActivatedHandler = { _, _, _, _, _, parameters, userData in
        guard let userData, let parameters else { return }
        let shortcut = unretained(userData, as: GlobalShortcut.self)

        let sessionVariant = g_variant_get_child_value(parameters, 0)
        let session = String(cString: g_variant_get_string(sessionVariant, nil))
        g_variant_unref(sessionVariant)
        guard session == shortcut.sessionHandle else { return }

        guard let shortcutsVariant = g_variant_get_child_value(parameters, 1) else { return }
        defer { g_variant_unref(shortcutsVariant) }
        shortcut.updateTriggerDescription(fromShortcuts: shortcutsVariant)
    }
}
