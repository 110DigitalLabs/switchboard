import AppKit

/// A session-navigation shortcut, decoded from a key-down event.
enum NavigationKey: Equatable {
    /// Cmd-1…Cmd-9, 1-based.
    case position(Int)
    /// Cmd-Up.
    case previous
    /// Cmd-Down.
    case next

    static let upArrowKeyCode: UInt16 = 126
    static let downArrowKeyCode: UInt16 = 125

    init?(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) {
        // Arrow keys also carry .numericPad and .function; ignore those.
        let relevant = modifiers.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        guard relevant == .command else { return nil }
        switch keyCode {
        case Self.upArrowKeyCode: self = .previous
        case Self.downArrowKeyCode: self = .next
        default:
            guard let characters, characters.count == 1, let digit = Int(characters),
                  (1...9).contains(digit) else { return nil }
            self = .position(digit)
        }
    }
}
