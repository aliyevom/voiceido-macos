import Carbon
import Foundation

final class HotkeyManager {
    var onPressed: @MainActor (UInt32) -> Void = { _ in }

    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var handlerInstalled = false

    @discardableResult
    func register(_ shortcut: Shortcut, id: UInt32) -> Bool {
        unregister(id)
        installHandlerIfNeeded()

        var hotKey: EventHotKeyRef?
        let carbonID = EventHotKeyID(signature: fourCC("TSNP"), id: id)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            carbonModifiers(shortcut),
            carbonID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard status == noErr, let hotKey else { return false }
        hotKeys[id] = hotKey
        return true
    }

    func unregister(_ id: UInt32) {
        guard let hotKey = hotKeys.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(hotKey)
    }

    func unregisterAll() {
        for id in Array(hotKeys.keys) {
            unregister(id)
        }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyHandler,
            1,
            &spec,
            userData,
            &handler
        )
        handlerInstalled = (status == noErr)
    }

    private func carbonModifiers(_ shortcut: Shortcut) -> UInt32 {
        var flags: UInt32 = 0
        if shortcut.command { flags |= UInt32(cmdKey) }
        if shortcut.shift { flags |= UInt32(shiftKey) }
        if shortcut.option { flags |= UInt32(optionKey) }
        if shortcut.control { flags |= UInt32(controlKey) }
        return flags
    }

    private func fourCC(_ string: String) -> OSType {
        var result: OSType = 0
        for scalar in string.unicodeScalars.prefix(4) {
            result = (result << 8) | OSType(scalar.value)
        }
        return result
    }
}

private func carbonHotKeyHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return noErr }
    let pressedID = hotKeyID.id
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            manager.onPressed(pressedID)
        }
    }
    return noErr
}
