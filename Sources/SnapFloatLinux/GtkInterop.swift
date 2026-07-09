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
    signal.withCString { csig in
        g_signal_connect_data(
            UnsafeMutableRawPointer(instance),
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
