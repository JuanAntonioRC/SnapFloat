import CGtk4Shim
import SnapFloatCore
import Foundation

/// Global keyboard shortcut for "Capture Area", recorded in-app (Settings'
/// "Change…") rather than through GNOME's own Settings > Keyboard > Custom
/// Shortcuts — confusing indirection for what should be a one-click "record
/// a shortcut" affordance. Registration itself picks one of two backends
/// per combination, transparently:
///
/// - No Super key: a direct X11 `XGrabKey` grab, like Flameshot/Spectacle.
///   Synchronous, no system dialogs, works before GTK/GDK are lazily
///   initialized (see GtkLazyInit.swift) since it uses its own Xlib
///   connection, independent of GDK's, pumped through the GLib main loop
///   via g_unix_fd_add.
/// - Super key involved: Mutter (GNOME's Wayland compositor) intercepts the
///   Super key at the compositor layer before XWayland clients ever see it
///   — a raw XGrabKey can never fire for these, no matter what. Only
///   org.freedesktop.portal.GlobalShortcuts, which talks to the compositor
///   directly, can actually claim them, so that's what's used instead. This
///   may show a one-time system confirmation dialog (GNOME's own, not a
///   detour through Settings) the first time a Super combination is bound.
///
/// Callers never need to know which backend is in play — `rebind` decides
/// from the modifier bits, and both paths funnel into the same
/// `onDescriptionChanged` callback and `AppSettingsStore` persistence.
final class GlobalHotkey {

    static let shared = GlobalHotkey()
    private static let shortcutId = "capture-area"

    private var x11Display: OpaquePointer?
    private var connection: OpaquePointer?
    private var onActivated: (() -> Void)?
    var onDescriptionChanged: ((String) -> Void)?

    // X11 backend state.
    private var grabbedKeycode: Int32?
    private var grabbedModifiers: UInt32?

    // Portal backend state.
    private var portalSessionHandle: String?
    private var portalSignalsSubscribed = false

    private(set) var triggerDescription: String?

    private init() {}

    /// Opens the dedicated X11 connection (for non-Super combinations) and
    /// grabs/binds the stored (or default) shortcut. `connection` is the
    /// shared session-bus connection (see AppController), needed for the
    /// portal backend.
    func start(connection: OpaquePointer, onActivated: @escaping () -> Void) {
        self.connection = connection
        self.onActivated = onActivated

        if let display = XOpenDisplay(nil) {
            self.x11Display = display
            _ = g_unix_fd_add(XConnectionNumber(display), G_IO_IN, Self.fdWatchCallback, retainedPointer(self))
        } else {
            NSLog("SnapFloat: no X11 display available — non-Super shortcuts disabled (Super-based ones still work via the portal)")
        }

        let settings = AppSettingsStore.shared
        rebind(keyval: settings.shortcutKeyval, modifiers: settings.shortcutModifiers) { ok in
            if !ok { NSLog("SnapFloat: could not (re)bind the saved global shortcut") }
        }
    }

    /// Grabs/binds `keyval` (an X11/GDK KeySym) + `modifiers` (an X11
    /// modifier mask — see `x11Modifiers(fromGdkState:)`) as the new global
    /// shortcut, releasing whatever was bound before. Persists the choice
    /// and calls `onDescriptionChanged` on success. The portal path is
    /// asynchronous (a system dialog may be involved), so this always
    /// reports back via `completion` rather than a return value.
    func rebind(keyval: UInt32, modifiers: UInt32, completion: @escaping (Bool) -> Void) {
        teardownCurrentBinding()

        if modifiers & 64 != 0 { // Mod4Mask (Super) — needs the portal.
            rebindViaPortal(keyval: keyval, modifiers: modifiers, completion: completion)
            return
        }

        guard let x11Display,
              case let keycode = Int32(XKeysymToKeycode(x11Display, KeySym(keyval))),
              keycode != 0,
              grabX11(keycode: keycode, modifiers: modifiers)
        else {
            completion(false)
            return
        }
        grabbedKeycode = keycode
        grabbedModifiers = modifiers
        commit(keyval: keyval, modifiers: modifiers, description: Self.describe(keyval: keyval, modifiers: modifiers))
        completion(true)
    }

    private func teardownCurrentBinding() {
        if let oldKeycode = grabbedKeycode, let oldModifiers = grabbedModifiers {
            ungrabX11(keycode: oldKeycode, modifiers: oldModifiers)
            grabbedKeycode = nil
            grabbedModifiers = nil
        }
        if let oldSession = portalSessionHandle {
            closePortalSession(oldSession)
            portalSessionHandle = nil
        }
    }

    private func commit(keyval: UInt32, modifiers: UInt32, description: String) {
        triggerDescription = description
        AppSettingsStore.shared.shortcutKeyval = keyval
        AppSettingsStore.shared.shortcutModifiers = modifiers
        onDescriptionChanged?(description)
    }

    /// Translates the modifier bits GTK reports for a keypress into the X11
    /// modifier mask `rebind` expects. GDK's Shift/Control/Alt bits are
    /// numerically identical to X11's core ones (ShiftMask=1, ControlMask=4,
    /// Mod1Mask=8 either way — see gdk/gdkenums.h); Super has no fixed
    /// core-protocol bit, so GDK invents a high one (1<<26) that's
    /// translated to Mod4Mask here, the conventional Super/Windows-key
    /// binding on virtually every Linux X11 setup. CapsLock/NumLock are
    /// deliberately dropped (see lockVariants).
    static func x11Modifiers(fromGdkState state: UInt32) -> UInt32 {
        let shiftControlAlt: UInt32 = 0b1101 // Shift(1) | Control(4) | Alt/Mod1(8)
        var mask = state & shiftControlAlt
        if state & 0x0400_0000 != 0 { mask |= 64 } // GDK_SUPER_MASK -> Mod4Mask
        return mask
    }

    // MARK: - X11 backend

    /// X11 requires a separate passive grab per combination of "irrelevant"
    /// modifiers the server happens to report (NumLock, CapsLock) — these
    /// four cover every common keyboard state.
    private static func lockVariants(of modifiers: UInt32) -> [CUnsignedInt] {
        let numLock: UInt32 = 16  // Mod2Mask
        let capsLock: UInt32 = 2  // LockMask
        return [modifiers, modifiers | numLock, modifiers | capsLock, modifiers | numLock | capsLock]
            .map { CUnsignedInt($0) }
    }

    @discardableResult
    private func grabX11(keycode: Int32, modifiers: UInt32) -> Bool {
        guard let x11Display else { return false }
        let root = XDefaultRootWindow(x11Display)
        return withErrorTrap {
            for variant in Self.lockVariants(of: modifiers) {
                XGrabKey(x11Display, keycode, variant, root, 1, GrabModeAsync, GrabModeAsync)
            }
        }
    }

    private func ungrabX11(keycode: Int32, modifiers: UInt32) {
        guard let x11Display else { return }
        let root = XDefaultRootWindow(x11Display)
        _ = withErrorTrap {
            for variant in Self.lockVariants(of: modifiers) {
                XUngrabKey(x11Display, keycode, variant, root)
            }
        }
    }

    /// Xlib's default error handler aborts the process on most protocol
    /// errors — every XGrabKey/XUngrabKey call needs this trap, since a
    /// conflicting grab (BadAccess) held by another app is an expected,
    /// recoverable outcome, not a bug. Restores whatever handler was
    /// installed before (GTK's own, once it's been lazily initialized), so
    /// this never permanently clobbers it. Returns false if an X11 error was
    /// trapped during `body`.
    private static var trappedErrorCode: CUnsignedChar?

    private static let errorTrapHandler: XErrorHandler = { _, event in
        if let event { trappedErrorCode = event.pointee.error_code }
        return 0
    }

    @discardableResult
    private func withErrorTrap(_ body: () -> Void) -> Bool {
        guard let x11Display else { return false }
        Self.trappedErrorCode = nil
        let previous = XSetErrorHandler(Self.errorTrapHandler)
        body()
        XSync(x11Display, 0)
        XSetErrorHandler(previous)
        if let code = Self.trappedErrorCode {
            NSLog("SnapFloat: X11 error \(code) (de)registering the global shortcut — probably already bound elsewhere")
            return false
        }
        return true
    }

    private typealias FDWatchHandler = @convention(c) (CInt, GIOCondition, UnsafeMutableRawPointer?) -> gboolean

    private static let fdWatchCallback: FDWatchHandler = { _, _, userData in
        guard let userData else { return 1 } // G_SOURCE_CONTINUE
        unretained(userData, as: GlobalHotkey.self).drainEvents()
        return 1
    }

    private func drainEvents() {
        guard let x11Display else { return }
        let relevantModifiers: UInt32 = 0b1101 // Shift | Control | Alt — Super never reaches here, see rebind
        while XPending(x11Display) > 0 {
            var event = XEvent()
            XNextEvent(x11Display, &event)
            guard event.type == KeyPress,
                  Int32(event.xkey.keycode) == grabbedKeycode,
                  event.xkey.state & relevantModifiers == grabbedModifiers
            else { continue }
            onActivated?()
        }
    }

    // MARK: - Portal backend (Super-key combinations)

    private func rebindViaPortal(keyval: UInt32, modifiers: UInt32, completion: @escaping (Bool) -> Void) {
        guard let connection else { completion(false); return }
        let createToken = "snapfloat_create\(UInt32.random(in: 0..<UInt32.max))"
        let params = gvTuple([gvDict([
            ("handle_token", gvString(createToken)),
            ("session_handle_token", gvString("snapfloat_session")),
        ])])

        portalRequest(
            connection: connection,
            interface: "org.freedesktop.portal.GlobalShortcuts",
            method: "CreateSession",
            params: params,
            handleToken: createToken
        ) { [weak self] responseCode, results in
            guard let self, responseCode == 0, let sessionHandle = gvLookupString(results, "session_handle") else {
                completion(false)
                return
            }
            self.bindPortalShortcut(sessionHandle: sessionHandle, keyval: keyval, modifiers: modifiers, completion: completion)
        }
    }

    private func bindPortalShortcut(sessionHandle: String, keyval: UInt32, modifiers: UInt32,
                                    completion: @escaping (Bool) -> Void) {
        guard let connection else { completion(false); return }
        let bindToken = "snapfloat_bind\(UInt32.random(in: 0..<UInt32.max))"
        let shortcutEntry = gvTuple([
            gvString(Self.shortcutId),
            gvDict([
                ("description", gvString("Capture Area")),
                ("preferred_trigger", gvString(Self.portalTriggerHint(keyval: keyval, modifiers: modifiers))),
            ]),
        ])
        let shortcuts = gvArray(type: "a(sa{sv})", [shortcutEntry])
        let options = gvDict([("handle_token", gvString(bindToken))])
        let params = gvTuple([gvObjectPath(sessionHandle), shortcuts, gvString(""), options])

        portalRequest(
            connection: connection,
            interface: "org.freedesktop.portal.GlobalShortcuts",
            method: "BindShortcuts",
            params: params,
            handleToken: bindToken
        ) { [weak self] responseCode, results in
            guard let self, responseCode == 0 else {
                completion(false)
                return
            }
            self.portalSessionHandle = sessionHandle
            self.subscribePortalSignalsIfNeeded()
            let description = self.extractTriggerDescription(fromBindResults: results)
                ?? Self.describe(keyval: keyval, modifiers: modifiers)
            self.commit(keyval: keyval, modifiers: modifiers, description: description)
            completion(true)
        }
    }

    private func closePortalSession(_ sessionHandle: String) {
        guard let connection else { return }
        g_dbus_connection_call(
            connection, "org.freedesktop.portal.Desktop", sessionHandle,
            "org.freedesktop.portal.Session", "Close",
            nil, nil, GDBusCallFlags(rawValue: 0), -1, nil, nil, nil
        )
    }

    private func extractTriggerDescription(fromBindResults results: OpaquePointer) -> String? {
        guard let shortcutsVariant = "shortcuts".withCString({
            g_variant_lookup_value(results, $0, g_variant_type_new("a(sa{sv})"))
        }) else { return nil }
        defer { g_variant_unref(shortcutsVariant) }
        return Self.extractTriggerDescription(fromShortcuts: shortcutsVariant)
    }

    /// - Parameter shortcuts: an `a(sa{sv})` array of (id, properties) pairs,
    ///   as found both in BindShortcuts results and the ShortcutsChanged signal.
    private static func extractTriggerDescription(fromShortcuts shortcuts: OpaquePointer) -> String? {
        let n = g_variant_n_children(shortcuts)
        for i in 0..<n {
            let entry = g_variant_get_child_value(shortcuts, i)
            defer { g_variant_unref(entry) }
            let idVariant = g_variant_get_child_value(entry, 0)
            let id = String(cString: g_variant_get_string(idVariant, nil))
            g_variant_unref(idVariant)
            guard id == shortcutId else { continue }
            guard let propsVariant = g_variant_get_child_value(entry, 1) else { return nil }
            defer { g_variant_unref(propsVariant) }
            return gvLookupString(propsVariant, "trigger_description")
        }
        return nil
    }

    private static func portalTriggerHint(keyval: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & 4 != 0  { parts.append("CTRL") }
        if modifiers & 1 != 0  { parts.append("SHIFT") }
        if modifiers & 8 != 0  { parts.append("ALT") }
        if modifiers & 64 != 0 { parts.append("SUPER") }
        let name = gdk_keyval_name(keyval).map { String(cString: $0) } ?? "?"
        parts.append(name.uppercased())
        return parts.joined(separator: "+")
    }

    // MARK: - Portal signals

    private typealias PortalSignalHandler = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        OpaquePointer?,
        UnsafeMutableRawPointer?
    ) -> Void

    /// App-lifetime subscriptions, established once — later rebinds via the
    /// portal only change `portalSessionHandle`, which these handlers filter
    /// on, so they don't need to be re-subscribed per session.
    private func subscribePortalSignalsIfNeeded() {
        guard !portalSignalsSubscribed, let connection else { return }
        portalSignalsSubscribed = true
        subscribe(signal: "Activated", handler: Self.onActivatedSignal, connection: connection)
        subscribe(signal: "ShortcutsChanged", handler: Self.onShortcutsChangedSignal, connection: connection)
    }

    private func subscribe(signal: String, handler: PortalSignalHandler, connection: OpaquePointer) {
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
                    _ = takeRetained(data, as: GlobalHotkey.self)
                }
            )
        }
    }

    private static let onActivatedSignal: PortalSignalHandler = { _, _, _, _, _, parameters, userData in
        guard let userData, let parameters else { return }
        let hotkey = unretained(userData, as: GlobalHotkey.self)

        let sessionVariant = g_variant_get_child_value(parameters, 0)
        let session = String(cString: g_variant_get_string(sessionVariant, nil))
        g_variant_unref(sessionVariant)
        guard session == hotkey.portalSessionHandle else { return }

        let idVariant = g_variant_get_child_value(parameters, 1)
        let id = String(cString: g_variant_get_string(idVariant, nil))
        g_variant_unref(idVariant)
        guard id == GlobalHotkey.shortcutId else { return }

        hotkey.onActivated?()
    }

    /// Keeps the displayed key combination current if the user rebinds it
    /// externally (e.g. GNOME Settings' Custom Shortcuts) while running.
    private static let onShortcutsChangedSignal: PortalSignalHandler = { _, _, _, _, _, parameters, userData in
        guard let userData, let parameters else { return }
        let hotkey = unretained(userData, as: GlobalHotkey.self)

        let sessionVariant = g_variant_get_child_value(parameters, 0)
        let session = String(cString: g_variant_get_string(sessionVariant, nil))
        g_variant_unref(sessionVariant)
        guard session == hotkey.portalSessionHandle else { return }

        guard let shortcutsVariant = g_variant_get_child_value(parameters, 1) else { return }
        defer { g_variant_unref(shortcutsVariant) }
        if let description = GlobalHotkey.extractTriggerDescription(fromShortcuts: shortcutsVariant) {
            hotkey.triggerDescription = description
            hotkey.onDescriptionChanged?(description)
        }
    }

    // MARK: - Description (X11 path — the portal path uses GNOME's own trigger_description)

    private static func describe(keyval: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & 4 != 0  { parts.append("Ctrl") }   // ControlMask
        if modifiers & 1 != 0  { parts.append("Shift") }  // ShiftMask
        if modifiers & 8 != 0  { parts.append("Alt") }    // Mod1Mask
        let name = gdk_keyval_name(keyval).map { String(cString: $0) } ?? "?"
        parts.append(name.count == 1 ? name.uppercased() : name)
        return parts.joined(separator: "+")
    }
}
