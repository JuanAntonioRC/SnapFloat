import CGtk4Shim
import Foundation

/// Calls org.freedesktop.portal.Screenshot. Two modes:
///
/// - `interactive: false` (the default flow, mirroring Flameshot): silently
///   grabs the whole desktop — GNOME asks "Allow SnapFloat to take
///   screenshots?" once, remembers the answer, and every later call is
///   instant. SnapFloat then shows its own crop overlay (CaptureOverlay).
/// - `interactive: true`: GNOME's own region/window/screen picker.
///
/// Either way the portal writes a PNG and hands us ownership of the file —
/// callers must move or delete it (it lands in ~/Pictures/Screenshots).
///
/// The request/response round trip itself lives in GtkInterop.swift's
/// portalRequest(), shared with GlobalShortcut.
enum PortalScreenshot {

    /// - Parameters:
    ///   - connection: the shared session-bus connection (see AppController).
    ///   - parentWindow: portal parent-window handle ("x11:0x..." — see
    ///     X11Interop.portalParentHandle) so consent dialogs get parented
    ///     to one of our windows; empty when capturing with no window open.
    static func request(on connection: OpaquePointer, interactive: Bool,
                        parentWindow: String = "",
                        completion: @escaping (URL?) -> Void) {
        let token = "snapfloat\(UInt32.random(in: 0..<UInt32.max))"
        let options = gvDict([
            ("handle_token", gvString(token)),
            ("interactive", gvBoolean(interactive)),
        ])
        let params = gvTuple([gvString(parentWindow), options])

        portalRequest(
            connection: connection,
            interface: "org.freedesktop.portal.Screenshot",
            method: "Screenshot",
            params: params,
            handleToken: token
        ) { responseCode, results in
            guard responseCode == 0, let uri = gvLookupString(results, "uri") else {
                completion(nil)
                return
            }
            completion(URL(string: uri))
        }
    }
}
