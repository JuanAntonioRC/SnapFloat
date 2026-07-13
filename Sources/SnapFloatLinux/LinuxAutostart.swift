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
                let contents = """
                [Desktop Entry]
                Type=Application
                Name=SnapFloat
                \(execLine)
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

    private static var execLine: String {
        if let snapName = ProcessInfo.processInfo.environment["SNAP_NAME"] {
            // Under snap confinement, /proc/self/exe resolves to a
            // revision-specific path inside the squashfs mount (e.g.
            // /snap/snapfloat/x1/...) that breaks on the next refresh —
            // /snap/bin/<name> is the stable entry point snapd keeps
            // pointing at the current revision. The allocator/renderer env
            // vars are already applied via snapcraft.yaml's `environment:`
            // for this launch path, so no env wrapper is needed here.
            return "Exec=/snap/bin/\(snapName)"
        }
        // argv[0] can be a relative path (e.g. `./snapfloat-linux`), useless
        // in a .desktop Exec line — resolve the real binary. Same
        // allocator/renderer tuning as the main .desktop entry — see its
        // comment for why.
        let exePath = (try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe"))
            ?? ProcessInfo.processInfo.arguments.first ?? "snapfloat-linux"
        return "Exec=env MALLOC_ARENA_MAX=2 MALLOC_MMAP_THRESHOLD_=131072 GSK_RENDERER=cairo \(exePath)"
    }
}
