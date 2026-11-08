import AppKit
import Carbon
import Foundation

enum KeyDisplay {
    static func shortcutString(_ shortcut: Shortcut) -> String {
        var symbols = ""
        if shortcut.control { symbols += "⌃" }
        if shortcut.option { symbols += "⌥" }
        if shortcut.shift { symbols += "⇧" }
        if shortcut.command { symbols += "⌘" }
        return symbols + label(for: shortcut.keyCode)
    }

    /// A single character NSMenuItem can show, without the modifier symbols.
    static func menuKeyEquivalent(for keyCode: UInt16) -> String? {
        guard let translated = translate(keyCode: keyCode), translated.count == 1 else { return nil }
        guard let scalar = translated.unicodeScalars.first else { return nil }
        guard scalar.value >= 32, scalar.value < 0xF700 else { return nil }
        return translated.lowercased()
    }

    static func label(for keyCode: UInt16) -> String {
        if let named = namedKey(keyCode) {
            return named
        }
        if let translated = translate(keyCode: keyCode), !translated.isEmpty {
            return translated.uppercased()
        }
        return "Key \(keyCode)"
    }

    private static func namedKey(_ keyCode: UInt16) -> String? {
        switch Int(keyCode) {
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Space: return "Space"
        case kVK_Delete: return "Delete"
        case kVK_Escape: return "Esc"
        case kVK_LeftArrow: return "Left"
        case kVK_RightArrow: return "Right"
        case kVK_UpArrow: return "Up"
        case kVK_DownArrow: return "Down"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return nil
        }
    }

    private static func translate(keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        guard let rawLayout = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayout).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }

        let keyboard = UnsafePointer<UCKeyboardLayout>(OpaquePointer(bytes))
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = UCKeyTranslate(
            keyboard,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
