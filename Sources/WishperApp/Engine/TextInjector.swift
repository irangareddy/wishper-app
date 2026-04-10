@preconcurrency import ApplicationServices
import AppKit
import Carbon
import Foundation

nonisolated final class TextInjector {

    private static let textElementRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole,
    ]

    func inject(_ text: String) -> Bool {
        // Strategy 1: Accessibility API — insert at cursor position
        if insertViaAccessibility(text) {
            print("[wishper] Injected via Accessibility API")
            return true
        }

        // Strategy 2: Clipboard + CGEvent Cmd+V
        if simulateCopyPaste(text) {
            print("[wishper] Injected via clipboard paste")
            return true
        }

        // Strategy 3: Clipboard only
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("[wishper] Text copied to clipboard — press Cmd+V to paste")
        return true
    }

    // MARK: - Approach 1: Accessibility API

    private func insertViaAccessibility(_ text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        // Find focused element
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let findError = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        )
        guard findError == .success, let focused = focusedRef else { return false }
        let element = focused as! AXUIElement

        // Check if it's a text element
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        guard let role = roleRef as? String, Self.textElementRoles.contains(role) else {
            return false
        }

        // Get current value (to verify change later)
        let currentValue = getStringValue(element, attribute: kAXValueAttribute)

        // Set kAXSelectedTextAttribute to insert at cursor position
        let setResult = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFTypeRef
        )
        guard setResult == .success else { return false }

        // Verify the value actually changed (Google Docs/VSCode silently ignore it)
        let newValue = getStringValue(element, attribute: kAXValueAttribute)
        if currentValue == newValue {
            // Value didn't change — this app doesn't support AX text insertion
            return false
        }

        return true
    }

    private func getStringValue(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value as? String
    }

    // MARK: - Approach 2: Clipboard + CGEvent Cmd+V

    private func simulateCopyPaste(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { return false }

        // Use cghidEventTap (not cgSessionEventTap) for proper keystroke simulation
        simulateKeyDown(key: CGKeyCode(kVK_ANSI_V), with: .maskCommand)

        return true
    }

    private func simulateKeyDown(key: CGKeyCode, with flags: CGEventFlags? = nil) {
        let source = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: key,
            keyDown: true
        )
        if let flags { event?.flags = flags }
        event?.post(tap: .cghidEventTap)
    }
}
