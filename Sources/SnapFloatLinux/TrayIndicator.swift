import CGtk4Shim
import Foundation

/// Publishes a tray icon by hand-implementing the org.kde.StatusNotifierItem
/// + com.canonical.dbusmenu D-Bus protocols directly over GDBus.
///
/// Why not libayatana-appindicator3? Its public header (app-indicator.h)
/// pulls in GTK3's gtk/gtk.h, which redefines the same type names (GtkWidget,
/// GtkWindow, ...) as GTK4's gtk/gtk.h already imported via CGtk4Shim in this
/// same Swift target — the two aren't safe to mix in one module. Ubuntu's
/// GNOME session ships the AppIndicator/KStatusNotifierItem shell extension
/// enabled by default, which is the thing that actually renders whatever
/// registers here — no GTK3 dependency needed on our side.
final class TrayIndicator {

    private let connection: OpaquePointer
    private let onCapture: () -> Void
    private let onSettings: () -> Void
    private let onQuit: () -> Void

    private static let sniObjectPath = "/StatusNotifierItem"
    private static let menuObjectPath = "/MenuBar"

    private struct MenuItem {
        let id: Int32
        let label: String?
        let isSeparator: Bool
        let action: (() -> Void)?
    }

    private let menuItems: [MenuItem]

    init(connection: OpaquePointer,
         onCapture: @escaping () -> Void,
         onSettings: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.connection = connection
        self.onCapture = onCapture
        self.onSettings = onSettings
        self.onQuit = onQuit
        self.menuItems = [
            MenuItem(id: 1, label: "Capture Area", isSeparator: false, action: onCapture),
            MenuItem(id: 2, label: nil, isSeparator: true, action: nil),
            MenuItem(id: 3, label: "Settings…", isSeparator: false, action: onSettings),
            MenuItem(id: 4, label: nil, isSeparator: true, action: nil),
            MenuItem(id: 5, label: "Quit", isSeparator: false, action: onQuit),
        ]
    }

    func start() {
        registerStatusNotifierItem()
        registerMenu()
        requestWatcherRegistration()
    }

    // MARK: - org.kde.StatusNotifierItem

    private static let sniXML = """
    <node>
      <interface name="org.kde.StatusNotifierItem">
        <property name="Category" type="s" access="read"/>
        <property name="Id" type="s" access="read"/>
        <property name="Title" type="s" access="read"/>
        <property name="Status" type="s" access="read"/>
        <property name="IconName" type="s" access="read"/>
        <property name="Menu" type="o" access="read"/>
        <property name="ItemIsMenu" type="b" access="read"/>
        <method name="Activate">
          <arg type="i" direction="in"/>
          <arg type="i" direction="in"/>
        </method>
        <method name="SecondaryActivate">
          <arg type="i" direction="in"/>
          <arg type="i" direction="in"/>
        </method>
      </interface>
    </node>
    """

    private func registerStatusNotifierItem() {
        guard let iface = Self.parseInterface(xml: Self.sniXML, interfaceName: "org.kde.StatusNotifierItem") else {
            NSLog("SnapFloat: failed to parse StatusNotifierItem introspection XML")
            return
        }
        var vtable = GDBusInterfaceVTable(
            method_call: Self.sniMethodCall,
            get_property: Self.sniGetProperty,
            set_property: nil,
            padding: (nil, nil, nil, nil, nil, nil, nil, nil)
        )
        var error: UnsafeMutablePointer<GError>?
        let userData = retainedPointer(self)
        _ = Self.sniObjectPath.withCString { path in
            withUnsafePointer(to: &vtable) { vtablePtr in
                g_dbus_connection_register_object(connection, path, iface, vtablePtr, userData, Self.releaseSelf, &error)
            }
        }
        if let error {
            NSLog("SnapFloat: register StatusNotifierItem failed – \(String(cString: error.pointee.message))")
        }
    }

    private static let sniMethodCall: GDBusInterfaceMethodCallFunc = { _, _, _, _, methodNamePtr, _, invocation, userData in
        guard let userData, let invocation else { return }
        let tray = unretained(userData, as: TrayIndicator.self)
        let method = methodNamePtr.map { String(cString: $0) } ?? ""
        switch method {
        case "Activate", "SecondaryActivate":
            tray.onCapture()
        default:
            break
        }
        g_dbus_method_invocation_return_value(invocation, nil)
    }

    private static let sniGetProperty: GDBusInterfaceGetPropertyFunc = { _, _, _, _, propertyNamePtr, _, _ in
        guard let propertyNamePtr else { return nil }
        switch String(cString: propertyNamePtr) {
        case "Category":  return gvString("ApplicationStatus")
        case "Id":        return gvString("com.snapfloat.SnapFloat")
        case "Title":     return gvString("SnapFloat")
        case "Status":    return gvString("Active")
        case "IconName":  return gvString("camera-photo-symbolic")
        case "Menu":      return gvObjectPath(TrayIndicator.menuObjectPath)
        case "ItemIsMenu": return gvBoolean(false)
        default: return nil
        }
    }

    // MARK: - com.canonical.dbusmenu

    private static let menuXML = """
    <node>
      <interface name="com.canonical.dbusmenu">
        <property name="Version" type="u" access="read"/>
        <property name="Status" type="s" access="read"/>
        <method name="GetLayout">
          <arg type="i" direction="in"/>
          <arg type="i" direction="in"/>
          <arg type="as" direction="in"/>
          <arg type="u" direction="out"/>
          <arg type="(ia{sv}av)" direction="out"/>
        </method>
        <method name="GetGroupProperties">
          <arg type="ai" direction="in"/>
          <arg type="as" direction="in"/>
          <arg type="a(ia{sv})" direction="out"/>
        </method>
        <method name="Event">
          <arg type="i" direction="in"/>
          <arg type="s" direction="in"/>
          <arg type="v" direction="in"/>
          <arg type="u" direction="in"/>
        </method>
        <method name="AboutToShow">
          <arg type="i" direction="in"/>
          <arg type="b" direction="out"/>
        </method>
      </interface>
    </node>
    """

    private func registerMenu() {
        guard let iface = Self.parseInterface(xml: Self.menuXML, interfaceName: "com.canonical.dbusmenu") else {
            NSLog("SnapFloat: failed to parse dbusmenu introspection XML")
            return
        }
        var vtable = GDBusInterfaceVTable(
            method_call: Self.menuMethodCall,
            get_property: Self.menuGetProperty,
            set_property: nil,
            padding: (nil, nil, nil, nil, nil, nil, nil, nil)
        )
        var error: UnsafeMutablePointer<GError>?
        let userData = retainedPointer(self)
        _ = Self.menuObjectPath.withCString { path in
            withUnsafePointer(to: &vtable) { vtablePtr in
                g_dbus_connection_register_object(connection, path, iface, vtablePtr, userData, Self.releaseSelf, &error)
            }
        }
        if let error {
            NSLog("SnapFloat: register dbusmenu failed – \(String(cString: error.pointee.message))")
        }
    }

    private static let menuGetProperty: GDBusInterfaceGetPropertyFunc = { _, _, _, _, propertyNamePtr, _, _ in
        guard let propertyNamePtr else { return nil }
        switch String(cString: propertyNamePtr) {
        case "Version": return gvUInt32(3)
        case "Status":  return gvString("normal")
        default: return nil
        }
    }

    private static let menuMethodCall: GDBusInterfaceMethodCallFunc = { _, _, _, _, methodNamePtr, parameters, invocation, userData in
        guard let userData, let invocation else { return }
        let tray = unretained(userData, as: TrayIndicator.self)
        let method = methodNamePtr.map { String(cString: $0) } ?? ""
        switch method {
        case "GetLayout":
            g_dbus_method_invocation_return_value(invocation, tray.buildGetLayoutReply())
        case "GetGroupProperties":
            g_dbus_method_invocation_return_value(invocation, gvTuple([gvArray(type: "a(ia{sv})", [])]))
        case "AboutToShow":
            g_dbus_method_invocation_return_value(invocation, gvTuple([gvBoolean(false)]))
        case "Event":
            if let parameters {
                let idVariant = g_variant_get_child_value(parameters, 0)
                let id = g_variant_get_int32(idVariant)
                g_variant_unref(idVariant)
                let typeVariant = g_variant_get_child_value(parameters, 1)
                let eventType = String(cString: g_variant_get_string(typeVariant, nil))
                g_variant_unref(typeVariant)
                if eventType == "clicked" {
                    tray.menuItems.first(where: { $0.id == id })?.action?()
                }
            }
            g_dbus_method_invocation_return_value(invocation, nil)
        default:
            g_dbus_method_invocation_return_value(invocation, nil)
        }
    }

    private func buildGetLayoutReply() -> OpaquePointer {
        let children: [OpaquePointer?] = menuItems.map { item in
            var props: [(String, OpaquePointer)] = []
            if item.isSeparator {
                props.append(("type", gvString("separator")))
            } else if let label = item.label {
                props.append(("label", gvString(label)))
            }
            let itemTuple = gvTuple([gvInt32(item.id), gvDict(props), gvArray(type: "av", [])])
            return g_variant_new_variant(itemTuple)
        }
        let rootProps = gvDict([("children-display", gvString("submenu"))])
        let rootTuple = gvTuple([gvInt32(0), rootProps, gvArray(type: "av", children)])
        return gvTuple([gvUInt32(1), rootTuple])
    }

    // MARK: - Watcher registration

    private func requestWatcherRegistration() {
        let uniqueName = String(cString: g_dbus_connection_get_unique_name(connection))
        let params = gvTuple([gvString(uniqueName)])
        g_dbus_connection_call(
            connection,
            "org.kde.StatusNotifierWatcher",
            "/StatusNotifierWatcher",
            "org.kde.StatusNotifierWatcher",
            "RegisterStatusNotifierItem",
            params, nil, GDBusCallFlags(rawValue: 0), -1, nil, nil, nil
        )
    }

    // MARK: - Helpers

    private static let releaseSelf: GDestroyNotify = { data in
        guard let data else { return }
        _ = takeRetained(data, as: TrayIndicator.self)
    }

    private static func parseInterface(xml: String, interfaceName: String) -> UnsafeMutablePointer<GDBusInterfaceInfo>? {
        var error: UnsafeMutablePointer<GError>?
        guard let nodeInfo = xml.withCString({ g_dbus_node_info_new_for_xml($0, &error) }) else {
            if let error { NSLog("SnapFloat: introspection XML parse failed – \(String(cString: error.pointee.message))") }
            return nil
        }
        return interfaceName.withCString { g_dbus_node_info_lookup_interface(nodeInfo, $0) }
    }
}
