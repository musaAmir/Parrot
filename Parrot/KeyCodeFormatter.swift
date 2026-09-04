//
//  KeyCodeFormatter.swift
//  Parrot
//
//  Turns a virtual key code into the label shown in the shortcut recorder.
//

import Carbon.HIToolbox
import AppKit
import Foundation

enum KeyCodeFormatter {

    /// Human-readable name for a virtual key code.
    ///
    /// This replaces a hand-written switch that only covered letters and a
    /// handful of specials, so recording ⌘⇧1 used to display "⌘⇧ ?". Anything
    /// that produces a character is read from the *current* keyboard layout, so
    /// AZERTY and Dvorak users see the key they actually pressed.
    static func string(for keyCode: UInt16) -> String {
        if let name = namedKeys[keyCode] {
            return name
        }
        if let character = characterFromCurrentLayout(keyCode), !character.isEmpty {
            return character.uppercased()
        }
        return "Key \(keyCode)"
    }

    /// Keys that either produce no character or read better by name.
    private static let namedKeys: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
        71: "Clear", 76: "Enter", 114: "Help",
        115: "Home", 116: "Page Up", 117: "⌦", 119: "End", 121: "Page Down",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
    ]

    private static func characterFromCurrentLayout(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,  // no modifiers: we want the key's own label, not ⌥-variants
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }

    /// The ⌃⌥⇧⌘ prefix, in the order macOS displays them.
    static func modifierString(_ flags: NSEvent.ModifierFlags) -> String {
        var parts = ""
        if flags.contains(.control) { parts += "⌃" }
        if flags.contains(.option) { parts += "⌥" }
        if flags.contains(.shift) { parts += "⇧" }
        if flags.contains(.command) { parts += "⌘" }
        return parts
    }

    static func shortcutString(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> String {
        let modifiers = modifierString(modifierFlags)
        let key = string(for: keyCode)
        return modifiers.isEmpty ? key : "\(modifiers) \(key)"
    }
}
