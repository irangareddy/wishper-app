import AppKit

struct HotkeyConfiguration: Codable, Equatable, Hashable {
    var modifierFlagsRawValue: UInt
    var keyCode: UInt16
    var keyChar: String?

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue).intersection(.deviceIndependentFlagsMask)
    }

    /// Symbol-based display (⌘ ⇧ ⌃ ⌥ fn) for UI badges
    var symbolString: String {
        if keyCode == 54 { return "⌘ Right" }
        if keyCode == 55, keyChar == nil, modifierFlags == [.command] { return "⌘ Left" }
        if keyCode == 63 { return "fn" }

        let mods = modifierFlags.symbolString
        let key = keyChar?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if let key, !key.isEmpty {
            return mods.isEmpty ? key : "\(mods) \(key)"
        }
        return mods.isEmpty ? "None" : mods
    }

    /// Text-based display for accessibility and logs
    var displayString: String {
        if keyCode == 54 { return "Right Command" }
        if keyCode == 55, keyChar == nil, modifierFlags == [.command] { return "Left Command" }
        if keyCode == 63 { return "Fn" }

        let modifiers = modifierFlags.displayString
        let key = keyChar?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if let key, !key.isEmpty {
            return modifiers.isEmpty ? key : "\(modifiers) + \(key)"
        }
        return modifiers.isEmpty ? "None" : modifiers
    }

    // Modifier-only hotkeys: modifierFlagsRawValue must be 0
    // The keyCode itself IS the modifier — no additional modifiers needed
    static let rightCommand = HotkeyConfiguration(
        modifierFlagsRawValue: 0,
        keyCode: 54,  // kVK_RightCommand
        keyChar: nil
    )

    static let fn = HotkeyConfiguration(
        modifierFlagsRawValue: 0,
        keyCode: 63,  // kVK_Function
        keyChar: nil
    )

    static let ctrlOption = HotkeyConfiguration(
        modifierFlagsRawValue: (NSEvent.ModifierFlags.control.union(.option)).rawValue,
        keyCode: 0,
        keyChar: nil
    )

    /// Control + Space — default hands-free
    static let fnSpace = HotkeyConfiguration(
        modifierFlagsRawValue: NSEvent.ModifierFlags.control.rawValue,
        keyCode: 49,  // kVK_Space
        keyChar: "Space"
    )

    /// Right Shift + Right Command + Space
    static let shiftCommandSpace = HotkeyConfiguration(
        modifierFlagsRawValue: (NSEvent.ModifierFlags.shift.union(.command)).rawValue,
        keyCode: 49,  // kVK_Space
        keyChar: "Space"
    )
}

extension NSEvent.ModifierFlags {
    var symbolString: String {
        var parts: [String] = []
        if contains(.control) { parts.append("⌃") }
        if contains(.option)  { parts.append("⌥") }
        if contains(.shift)   { parts.append("⇧") }
        if contains(.command) { parts.append("⌘") }
        if contains(.function) { parts.append("fn") }
        return parts.joined(separator: "")
    }

    var displayString: String {
        var parts: [String] = []
        if contains(.control) { parts.append("Control") }
        if contains(.option)  { parts.append("Option") }
        if contains(.shift)   { parts.append("Shift") }
        if contains(.command) { parts.append("Command") }
        if contains(.function) { parts.append("Fn") }
        return parts.joined(separator: " + ")
    }
}
