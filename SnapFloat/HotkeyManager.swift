import Carbon

/// Registers a global hotkey using Carbon (no Accessibility permission required).
/// Default: Shift + Cmd + 2
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

    func register() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Non-capturing closure → Swift bridges it to a C function pointer automatically
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

        // Shift + Cmd + 2  (kVK_ANSI_2 = 0x13)
        let hotKeyID = EventHotKeyID(signature: 0x534E4650 /* "SNFP" */, id: 1)
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
        if let ref = handlerRef { RemoveEventHandler(ref) }
    }
}
