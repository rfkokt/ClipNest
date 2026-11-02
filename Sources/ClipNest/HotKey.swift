import Carbon

/// Global shortcut through Carbon, which works without Accessibility permission.
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false

    func register(_ combo: HotKeyCombo) {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil

        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKeyManager.shared.onPress?() }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }

        let id = EventHotKeyID(signature: OSType(0x434C_4E53), id: 1) // "CLNS"
        RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }
}
