import CGtk4Shim
import SnapFloatCore
import Foundation

/// Global keyboard shortcut for "Capture Area", registered directly via X11
/// (XGrabKey) rather than the org.freedesktop.portal.GlobalShortcuts portal.
/// The portal only lets the key combination be *changed* through GNOME's own
/// Settings app (Keyboard → View and Customize Shortcuts) — confusing
/// indirection for what should be a one-click "record a shortcut" affordance
/// in the app itself. This mirrors how Flameshot/Spectacle do it, at the
/// cost of only working under X11/XWayland — already a hard requirement
/// elsewhere in this app (see X11Interop.swift).
///
/// Uses its own Xlib connection, independent of GDK's, pumped through the
/// GLib main loop via g_unix_fd_add — so the shortcut is grabbed and live
/// from the moment the app launches, before GTK/GDK are lazily initialized
/// for the first window (see GtkLazyInit.swift).
final class GlobalHotkey {

    static let shared = GlobalHotkey()

    private var display: OpaquePointer?
    private var onActivated: (() -> Void)?
    var onDescriptionChanged: ((String) -> Void)?

    private var grabbedKeycode: Int32?
    private var grabbedModifiers: UInt32?
    private(set) var triggerDescription: String?

    private init() {}

    /// Opens the dedicated X11 connection and grabs the stored (or default)
    /// shortcut. A no-op, logged-and-disabled feature when no X11 display is
    /// available (pure Wayland, no XWayland).
    func start(onActivated: @escaping () -> Void) {
        self.onActivated = onActivated
        guard let display = XOpenDisplay(nil) else {
            NSLog("SnapFloat: no X11 display available — global shortcut disabled")
            return
        }
        self.display = display
        _ = g_unix_fd_add(XConnectionNumber(display), G_IO_IN, Self.fdWatchCallback, retainedPointer(self))

        let settings = AppSettingsStore.shared
        if !rebind(keyval: settings.shortcutKeyval, modifiers: settings.shortcutModifiers) {
            NSLog("SnapFloat: could not grab the default global shortcut (already bound elsewhere?)")
        }
    }

    /// Grabs `keyval` (an X11/GDK KeySym) + `modifiers` (an X11 modifier
    /// mask — see `x11Modifiers(fromGdkState:)`) as the new global shortcut,
    /// releasing whatever was grabbed before and persisting the choice.
    /// Returns false (and restores the previous grab) if `keyval` has no
    /// keycode in the current layout, or the combination is already grabbed
    /// by another app.
    @discardableResult
    func rebind(keyval: UInt32, modifiers: UInt32) -> Bool {
        guard let display else { return false }
        let keycode = Int32(XKeysymToKeycode(display, KeySym(keyval)))
        guard keycode != 0 else { return false }

        if let oldKeycode = grabbedKeycode, let oldModifiers = grabbedModifiers {
            ungrab(keycode: oldKeycode, modifiers: oldModifiers)
        }

        guard grab(keycode: keycode, modifiers: modifiers) else {
            // Leave the app with something bound rather than nothing.
            if let oldKeycode = grabbedKeycode, let oldModifiers = grabbedModifiers {
                _ = grab(keycode: oldKeycode, modifiers: oldModifiers)
            }
            return false
        }

        grabbedKeycode = keycode
        grabbedModifiers = modifiers
        let description = Self.describe(keyval: keyval, modifiers: modifiers)
        triggerDescription = description

        AppSettingsStore.shared.shortcutKeyval = keyval
        AppSettingsStore.shared.shortcutModifiers = modifiers
        onDescriptionChanged?(description)
        return true
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

    // MARK: - Grab / ungrab

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
    private func grab(keycode: Int32, modifiers: UInt32) -> Bool {
        guard let display else { return false }
        let root = XDefaultRootWindow(display)
        return withErrorTrap {
            for variant in Self.lockVariants(of: modifiers) {
                XGrabKey(display, keycode, variant, root, 1, GrabModeAsync, GrabModeAsync)
            }
        }
    }

    private func ungrab(keycode: Int32, modifiers: UInt32) {
        guard let display else { return }
        let root = XDefaultRootWindow(display)
        _ = withErrorTrap {
            for variant in Self.lockVariants(of: modifiers) {
                XUngrabKey(display, keycode, variant, root)
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
        guard let display else { return false }
        Self.trappedErrorCode = nil
        let previous = XSetErrorHandler(Self.errorTrapHandler)
        body()
        XSync(display, 0)
        XSetErrorHandler(previous)
        if let code = Self.trappedErrorCode {
            NSLog("SnapFloat: X11 error \(code) (de)registering the global shortcut — probably already bound elsewhere")
            return false
        }
        return true
    }

    // MARK: - Event pump

    private typealias FDWatchHandler = @convention(c) (CInt, GIOCondition, UnsafeMutableRawPointer?) -> gboolean

    private static let fdWatchCallback: FDWatchHandler = { _, _, userData in
        guard let userData else { return 1 } // G_SOURCE_CONTINUE
        unretained(userData, as: GlobalHotkey.self).drainEvents()
        return 1
    }

    private func drainEvents() {
        guard let display else { return }
        let relevantModifiers: UInt32 = 0b1101 | 64 // Shift | Control | Alt | Super — see x11Modifiers
        while XPending(display) > 0 {
            var event = XEvent()
            XNextEvent(display, &event)
            guard event.type == KeyPress,
                  Int32(event.xkey.keycode) == grabbedKeycode,
                  event.xkey.state & relevantModifiers == grabbedModifiers
            else { continue }
            onActivated?()
        }
    }

    // MARK: - Description

    private static func describe(keyval: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & 4 != 0  { parts.append("Ctrl") }   // ControlMask
        if modifiers & 1 != 0  { parts.append("Shift") }  // ShiftMask
        if modifiers & 8 != 0  { parts.append("Alt") }    // Mod1Mask
        if modifiers & 64 != 0 { parts.append("Super") }  // Mod4Mask
        let name = gdk_keyval_name(keyval).map { String(cString: $0) } ?? "?"
        parts.append(name.count == 1 ? name.uppercased() : name)
        return parts.joined(separator: "+")
    }
}
