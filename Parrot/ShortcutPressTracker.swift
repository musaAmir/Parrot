import CoreGraphics

struct KeyBinding: Equatable {
    var keyCode: UInt16
    var flags: CGEventFlags
    var isEnabled: Bool

    func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        isEnabled && keyCode == self.keyCode && flags == self.flags
    }

    static let disabled = KeyBinding(keyCode: 0, flags: [], isEnabled: false)
}

/// A key-up belongs to the shortcut that consumed its key-down, even if the
/// user released a modifier or edited the binding in the meantime.
struct ShortcutPressTracker {
    enum Action { case holdDown, holdUp, toggleDown, toggleUp, consume }
    private var heldKey: UInt16?
    private var toggledKey: UInt16?

    mutating func handle(keyCode: UInt16, flags: CGEventFlags, isDown: Bool,
                         isRepeat: Bool, hold: KeyBinding, toggle: KeyBinding) -> Action? {
        if !isDown {
            if heldKey == keyCode { heldKey = nil; return .holdUp }
            if toggledKey == keyCode { toggledKey = nil; return .toggleUp }
            return nil
        }
        if heldKey == keyCode || toggledKey == keyCode { return .consume }
        guard !isRepeat else { return nil }
        if hold.matches(keyCode: keyCode, flags: flags) {
            heldKey = keyCode
            return .holdDown
        }
        if toggle.matches(keyCode: keyCode, flags: flags) {
            toggledKey = keyCode
            return .toggleDown
        }
        return nil
    }

    mutating func reset() { heldKey = nil; toggledKey = nil }
}
