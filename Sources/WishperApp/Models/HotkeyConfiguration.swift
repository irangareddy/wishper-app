import AppKit

struct HotkeyConfiguration: Codable, Equatable {
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

    static let rightCommand = HotkeyConfiguration(
        modifierFlagsRawValue: NSEvent.ModifierFlags.command.rawValue,
        keyCode: 54,
        keyChar: nil
    )

    static let fn = HotkeyConfiguration(
        modifierFlagsRawValue: NSEvent.ModifierFlags.function.rawValue,
        keyCode: 63,
        keyChar: nil
    )

    static let ctrlOption = HotkeyConfiguration(
        modifierFlagsRawValue: (NSEvent.ModifierFlags.control.union(.option)).rawValue,
        keyCode: 0,
        keyChar: nil
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
