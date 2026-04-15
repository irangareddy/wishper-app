import AppKit

struct HotkeyConfiguration: Codable, Equatable, Hashable {
    var modifierFlagsRawValue: UInt
    var keyCode: UInt16
    var keyChar: String?

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue).intersection(.deviceIndependentFlagsMask)
    }

    var displayString: String {
        if keyCode == 54 {
            return "Right Command"
        }

        if keyCode == 55, keyChar == nil, modifierFlags == [.command] {
            return "Left Command"
        }

        if keyCode == 63 {
            return "Fn"
        }

        let modifiers = modifierFlags.displayString
        let key = keyChar?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if let key, !key.isEmpty {
            if modifiers.isEmpty {
                return key
            }
            return "\(modifiers) + \(key)"
        }

        if !modifiers.isEmpty {
            return modifiers
        }

        return "None"
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

    /// Fn + Space — default hands-free toggle
    static let fnSpace = HotkeyConfiguration(
        modifierFlagsRawValue: NSEvent.ModifierFlags.function.rawValue,
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
    var displayString: String {
        var parts: [String] = []

        if contains(.control) {
            parts.append("Control")
        }
        if contains(.option) {
            parts.append("Option")
        }
        if contains(.shift) {
            parts.append("Shift")
        }
        if contains(.command) {
            parts.append("Command")
        }
        if contains(.function) {
            parts.append("Fn")
        }

        return parts.joined(separator: " + ")
    }
}
