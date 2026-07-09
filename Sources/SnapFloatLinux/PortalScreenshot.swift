import CGtk4Shim
import Foundation

/// Calls org.freedesktop.portal.Screenshot with interactive:true. On GNOME
/// this shows GNOME's own region/window/screen picker — Wayland doesn't let
/// an unprivileged client draw its own capture overlay (see README for why)
/// — SnapFloat picks up the resulting image once the user finishes.
///
/// Note: GVariant/GDBusConnection import into Swift as bare `OpaquePointer`
/// rather than a named typed pointer — see Sources/CGtk4Shim/shim.h.
enum PortalScreenshot {

    private typealias DBusSignalHandler = @convention(c) (
        OpaquePointer?, // GDBusConnection*
        UnsafePointer<CChar>?, // sender_name
        UnsafePointer<CChar>?, // object_path
        UnsafePointer<CChar>?, // interface_name
        UnsafePointer<CChar>?, // signal_name
        OpaquePointer?, // GVariant* parameters
        UnsafeMutableRawPointer? // user_data
    ) -> Void

    private final class PendingRequest {
        let completion: (URL?) -> Void
        init(completion: @escaping (URL?) -> Void) { self.completion = completion }
    }

    /// - Parameter connection: the shared session-bus connection (see AppController).
    static func request(on connection: OpaquePointer, completion: @escaping (URL?) -> Void) {
        let uniqueName = String(cString: g_dbus_connection_get_unique_name(connection))
        // Per the XDG portal spec: request object path = well-known prefix +
        // sender name (':' stripped, '.' -> '_') + our chosen handle_token.
        let sender = uniqueName.dropFirst().replacingOccurrences(of: ".", with: "_")
        let token = "snapfloat\(UInt32.random(in: 0..<UInt32.max))"
        let requestPath = "/org/freedesktop/portal/desktop/request/\(sender)/\(token)"

        let pending = PendingRequest(completion: completion)
        let userData = retainedPointer(pending)

        _ = requestPath.withCString { pathC in
            g_dbus_connection_signal_subscribe(
                connection,
                "org.freedesktop.portal.Desktop",
                "org.freedesktop.portal.Request",
                "Response",
                pathC,
                nil,
                GDBusSignalFlags(rawValue: 0),
                onResponse,
                userData,
                { data in
                    guard let data else { return }
                    _ = takeRetained(data, as: PendingRequest.self)
                }
            )
        }

        let optionsBuilder = g_variant_builder_new(g_variant_type_new("a{sv}"))
        addOption(optionsBuilder, key: "handle_token", value: g_variant_new_string(token))
        addOption(optionsBuilder, key: "interactive", value: g_variant_new_boolean(1))
        let optionsVariant = g_variant_builder_end(optionsBuilder)
        g_variant_builder_unref(optionsBuilder)

        var children: [OpaquePointer?] = [g_variant_new_string(""), optionsVariant]
        let paramsVariant = children.withUnsafeMutableBufferPointer { buf in
            g_variant_new_tuple(buf.baseAddress, 2)
        }

        g_dbus_connection_call(
            connection,
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.Screenshot",
            "Screenshot",
            paramsVariant, nil, GDBusCallFlags(rawValue: 0), -1, nil, nil, nil
        )
    }

    private static func addOption(_ builder: UnsafeMutablePointer<GVariantBuilder>?, key: String, value: OpaquePointer!) {
        key.withCString { k in
            let entry = g_variant_new_dict_entry(g_variant_new_string(k), g_variant_new_variant(value))
            g_variant_builder_add_value(builder, entry)
        }
    }

    private static let onResponse: DBusSignalHandler = { _, _, _, _, _, parameters, userData in
        guard let userData, let parameters else { return }
        let pending = takeRetained(userData, as: PendingRequest.self)

        let responseCodeVariant = g_variant_get_child_value(parameters, 0)
        let responseCode = g_variant_get_uint32(responseCodeVariant)
        g_variant_unref(responseCodeVariant)

        guard responseCode == 0 else {
            pending.completion(nil)
            return
        }

        let resultsVariant = g_variant_get_child_value(parameters, 1)
        defer { g_variant_unref(resultsVariant) }

        var url: URL?
        "uri".withCString { k in
            if let uriVariant = g_variant_lookup_value(resultsVariant, k, g_variant_type_new("s")) {
                let uriString = String(cString: g_variant_get_string(uriVariant, nil))
                g_variant_unref(uriVariant)
                url = URL(string: uriString)
            }
        }
        pending.completion(url)
    }
}
