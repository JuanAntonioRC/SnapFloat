import CGtk4Shim

// Thin, hand-written Swift wrappers over the raw GTK4/GLib C API exposed by
// CGtk4Shim. There's no binding generator involved — Swift's Clang importer
// exposes every function/struct from <gtk/gtk.h> and <gio/gio.h> directly;
// these helpers just make the handful of GObject-signal / widget-building
// patterns used elsewhere in this target easier to read.

/// A no-capture C callback taking (instance, user_data).
typealias GSimpleHandler = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void

@discardableResult
func gConnect<Instance>(_ instance: UnsafeMutablePointer<Instance>, _ signal: String,
                        data: UnsafeMutableRawPointer? = nil,
                        _ handler: @escaping GSimpleHandler) -> CUnsignedLong {
    gConnectRaw(UnsafeMutableRawPointer(instance), signal, data: data, handler)
}

/// Overload for the handful of GObject types (GtkGestureDrag, GtkGestureClick, ...)
/// that import as bare `OpaquePointer` rather than a named typed pointer —
/// see the ClangImporter note in GtkInterop.swift's header comment.
@discardableResult
func gConnect<Handler>(_ instance: OpaquePointer, _ signal: String,
                       data: UnsafeMutableRawPointer? = nil,
                       _ handler: Handler) -> CUnsignedLong {
    gConnectRaw(UnsafeMutableRawPointer(instance), signal, data: data, handler)
}

@discardableResult
private func gConnectRaw<Handler>(_ instance: UnsafeMutableRawPointer, _ signal: String,
                                  data: UnsafeMutableRawPointer?, _ handler: Handler) -> CUnsignedLong {
    signal.withCString { csig in
        g_signal_connect_data(
            instance,
            csig,
            unsafeBitCast(handler, to: GCallback.self),
            data,
            nil,
            GConnectFlags(rawValue: 0)
        )
    }
}

/// GObject's C "inheritance" is struct embedding (a GtkWindow's first field
/// is a GtkWidget, whose first field is a GObject, ...), so reinterpreting a
/// pointer between a type and one of its GObject ancestors/descendants is
/// exactly what every GTK_WINDOW()/G_APPLICATION()-style cast macro does in
/// C. Those macros aren't imported by Swift (they're preprocessor macros),
/// so this is the equivalent: a plain pointer rebind.
func gobjectCast<From, To>(_ ptr: UnsafeMutablePointer<From>, to: To.Type) -> UnsafeMutablePointer<To> {
    UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: To.self)
}

/// Bridges `self` (a class instance) into a `gpointer` for signal user_data,
/// mirroring the Unmanaged pattern already used in SnapFloat/HotkeyManager.swift.
func retainedPointer<T: AnyObject>(_ instance: T) -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(instance).toOpaque()
}

/// For user_data that's scoped to something already kept alive elsewhere
/// (e.g. a child widget's signal reaching back to its long-lived parent
/// Context) — no matching takeRetained is needed or expected.
func unretainedPointer<T: AnyObject>(_ instance: T) -> UnsafeMutableRawPointer {
    Unmanaged.passUnretained(instance).toOpaque()
}

func takeRetained<T: AnyObject>(_ ptr: UnsafeMutableRawPointer, as type: T.Type) -> T {
    Unmanaged<T>.fromOpaque(ptr).takeRetainedValue()
}

func unretained<T: AnyObject>(_ ptr: UnsafeMutableRawPointer, as type: T.Type) -> T {
    Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
}

// MARK: - GVariant construction helpers
//
// GVariant/GDBusConnection import as bare `OpaquePointer` (see shim.h note).
// These build GVariant trees using only fixed-signature functions — GLib's
// varargs-based g_variant_new(format, ...)/g_variant_lookup(...) are
// deliberately avoided here to sidestep any risk of C-varargs/Swift
// calling-convention mismatches.

func gvString(_ s: String) -> OpaquePointer { s.withCString { g_variant_new_string($0) } }
func gvBoolean(_ b: Bool) -> OpaquePointer { g_variant_new_boolean(b ? 1 : 0) }
func gvInt32(_ i: Int32) -> OpaquePointer { g_variant_new_int32(i) }
func gvUInt32(_ u: UInt32) -> OpaquePointer { g_variant_new_uint32(u) }
func gvObjectPath(_ s: String) -> OpaquePointer { s.withCString { g_variant_new_object_path($0) } }

func gvDictEntry(_ key: String, _ value: OpaquePointer) -> OpaquePointer {
    key.withCString { g_variant_new_dict_entry(g_variant_new_string($0), g_variant_new_variant(value)) }
}

/// Builds an `a{sv}` dictionary.
func gvDict(_ entries: [(String, OpaquePointer)]) -> OpaquePointer {
    let builder = g_variant_builder_new(g_variant_type_new("a{sv}"))
    for (k, v) in entries {
        g_variant_builder_add_value(builder, gvDictEntry(k, v))
    }
    let result = g_variant_builder_end(builder)!
    g_variant_builder_unref(builder)
    return result
}

/// Builds an array of the given GVariant type signature (e.g. "av", "as").
func gvArray(type: String, _ items: [OpaquePointer?]) -> OpaquePointer {
    let builder = g_variant_builder_new(g_variant_type_new(type))
    for item in items {
        g_variant_builder_add_value(builder, item)
    }
    let result = g_variant_builder_end(builder)!
    g_variant_builder_unref(builder)
    return result
}

func gvTuple(_ items: [OpaquePointer?]) -> OpaquePointer {
    var items = items
    let count = items.count
    return items.withUnsafeMutableBufferPointer { buf in
        g_variant_new_tuple(buf.baseAddress, gsize(count))
    }
}

// MARK: - XDG portal request/response helper

/// Calls a method on org.freedesktop.portal.Desktop that returns a Request
/// object handle, subscribes to that Request's `Response` signal *before*
/// making the call (predicting the object path from a caller-chosen
/// handle_token, per the portal spec), and invokes `completion` with
/// (responseCode, resultsDict) once the signal fires. Used by both
/// PortalScreenshot and GlobalShortcut for their D-Bus round trips.
private typealias PortalSignalHandler = @convention(c) (
    OpaquePointer?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    OpaquePointer?,
    UnsafeMutableRawPointer?
) -> Void

private final class PortalPendingRequest {
    let completion: (UInt32, OpaquePointer) -> Void
    var subscriptionId: guint = 0
    init(completion: @escaping (UInt32, OpaquePointer) -> Void) { self.completion = completion }
}

private let portalResponseHandler: PortalSignalHandler = { connection, _, _, _, _, parameters, userData in
    guard let userData, let parameters else { return }
    let pending = unretained(userData, as: PortalPendingRequest.self)

    let responseCodeVariant = g_variant_get_child_value(parameters, 0)
    let responseCode = g_variant_get_uint32(responseCodeVariant)
    g_variant_unref(responseCodeVariant)

    if let resultsVariant = g_variant_get_child_value(parameters, 1) {
        pending.completion(responseCode, resultsVariant)
        g_variant_unref(resultsVariant)
    }

    // A Request object emits Response exactly once — unsubscribe now.
    // The subscription's destroy notify (fired from an idle) is the sole
    // owner of the retain taken in portalRequest().
    if pending.subscriptionId != 0, let connection {
        let id = pending.subscriptionId
        pending.subscriptionId = 0
        g_dbus_connection_signal_unsubscribe(connection, id)
    }
}

@discardableResult
func portalRequest(
    connection: OpaquePointer,
    interface: String,
    method: String,
    params: OpaquePointer,
    objectPath: String = "/org/freedesktop/portal/desktop",
    busName: String = "org.freedesktop.portal.Desktop",
    handleToken: String,
    completion: @escaping (UInt32, OpaquePointer) -> Void
) -> String {
    let uniqueName = String(cString: g_dbus_connection_get_unique_name(connection))
    let sender = uniqueName.dropFirst().replacingOccurrences(of: ".", with: "_")
    let requestPath = "/org/freedesktop/portal/desktop/request/\(sender)/\(handleToken)"

    let pending = PortalPendingRequest(completion: completion)
    let userData = retainedPointer(pending)

    pending.subscriptionId = requestPath.withCString { pathC in
        g_dbus_connection_signal_subscribe(
            connection, busName, "org.freedesktop.portal.Request", "Response", pathC, nil,
            GDBusSignalFlags(rawValue: 0), portalResponseHandler, userData,
            { data in
                guard let data else { return }
                _ = takeRetained(data, as: PortalPendingRequest.self)
            }
        )
    }

    busName.withCString { bn in
    objectPath.withCString { op in
    interface.withCString { ifc in
    method.withCString { m in
        g_dbus_connection_call(connection, bn, op, ifc, m, params, nil,
                               GDBusCallFlags(rawValue: 0), -1, nil, nil, nil)
    }}}}

    return requestPath
}

/// Looks up a string-typed (`s` or `o`) value in an `a{sv}` results dict.
func gvLookupString(_ dict: OpaquePointer, _ key: String) -> String? {
    key.withCString { k in
        guard let v = g_variant_lookup_value(dict, k, nil) else { return nil }
        defer { g_variant_unref(v) }
        guard let cstr = g_variant_get_string(v, nil) else { return nil }
        return String(cString: cstr)
    }
}
