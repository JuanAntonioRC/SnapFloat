import Carbon.HIToolbox

/// Registers a global hotkey using Carbon (no Accessibility permission required).
/// Default: Shift + Cmd + 2
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    func register() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallApplicationEventHandler(
            { (_, _, userData) -> OSStatus in
                guard let ptr = userData else { return noErr }
                Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue().callback()
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            nil
        )

        // Shift + Cmd + 2  (kVK_ANSI_2 = 0x13)
        var hotKeyID = EventHotKeyID(signature: 0x534E4650 /* "SNFP" */, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_2),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
    }
}
