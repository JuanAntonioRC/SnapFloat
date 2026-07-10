import Foundation

/// "Launch at login" via the XDG autostart convention (~/.config/autostart),
/// mirroring SettingsManager.launchAtLogin on macOS (which uses SMAppService).
enum LinuxAutostart {
    private static var autostartPath: String {
        let configHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".config")
        return (configHome as NSString).appendingPathComponent("autostart/com.snapfloat.SnapFloat.desktop")
    }

    static var isEnabled: Bool {
        get { FileManager.default.fileExists(atPath: autostartPath) }
        set {
            let fm = FileManager.default
            if newValue {
                let dir = (autostartPath as NSString).deletingLastPathComponent
                try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                // argv[0] can be a relative path (e.g. `./snapfloat-linux`),
                // useless in a .desktop Exec line — resolve the real binary.
                let exePath = (try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe"))
                    ?? ProcessInfo.processInfo.arguments.first ?? "snapfloat-linux"
                let contents = """
                [Desktop Entry]
                Type=Application
                Name=SnapFloat
                Exec=\(exePath)
                Icon=com.snapfloat.SnapFloat
                X-GNOME-Autostart-enabled=true
                NoDisplay=true
                """
                try? contents.write(toFile: autostartPath, atomically: true, encoding: .utf8)
            } else {
                try? fm.removeItem(atPath: autostartPath)
            }
        }
    }
}
