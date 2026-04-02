import AppKit
import Carbon

/// Registers a global hotkey using Carbon (no Accessibility permission required).
///
/// Note: InstallApplicationEventHandler is a C macro and is not available in Swift.
/// We call InstallEventHandler(GetApplicationEventTarget(), ...) directly instead.
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        if handlerRef == nil {
            var eventSpec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: OSType(kEventHotKeyPressed)
            )

            let selfPtr = Unmanaged.passUnretained(self).toOpaque()

            let handler: EventHandlerProcPtr = { (_, _, userData) -> OSStatus in
                guard let ptr = userData else { return noErr }
                Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue().callback()
                return noErr
            }

            InstallEventHandler(
                GetApplicationEventTarget(),
                handler,
                1,
                &eventSpec,
                selfPtr,
                &handlerRef
            )
        }

        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }

        let hotKeyID = EventHotKeyID(signature: 0x534E4650 /* "SNFP" */, id: 1)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = handlerRef { RemoveEventHandler(ref) }
    }

    // MARK: – Modifier conversion

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    // MARK: – Display string

    static func modifiersString(for modifiers: UInt32) -> String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { result += "⌘" }
        return result
    }

    static func displayString(forKeyCode keyCode: UInt32, modifiers: UInt32) -> String {
        modifiersString(for: modifiers) + keyName(forKeyCode: keyCode)
    }

    private static func keyName(forKeyCode keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
            0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
            0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
            0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
            0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
            0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
            0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M",
            0x2F: ".", 0x32: "`",
            0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫",
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
            0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
            0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
            0x75: "⌦", 0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",
            0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        ]
        return names[keyCode] ?? "?"
    }
}
