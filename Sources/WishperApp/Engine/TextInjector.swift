@preconcurrency import ApplicationServices
import AppKit
import Carbon
import Foundation

nonisolated final class TextInjector {

    private static let textElementRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole,
    ]

    func inject(_ text: String) -> Bool {
        // Always put text on clipboard first
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Strategy 1: Accessibility API — direct insert at cursor
        if insertViaAccessibility(text) {
            print("[wishper] Injected via Accessibility API")
            return true
        }

        // Strategy 2: CGEvent Cmd+V via cghidEventTap — clipboard already set, paste immediately
        simulatePaste()
        print("[wishper] Injected via CGEvent Cmd+V")
        return true
    }

    // MARK: - Strategy 1: Accessibility API

    private func insertViaAccessibility(_ text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let findError = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        )
        guard findError == .success, let focused = focusedRef else { return false }
        let element = focused as! AXUIElement

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        guard let role = roleRef as? String, Self.textElementRoles.contains(role) else {
            return false
        }

        let currentValue = getStringValue(element, attribute: kAXValueAttribute)
        let setResult = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFTypeRef
        )
        guard setResult == .success else { return false }

        let newValue = getStringValue(element, attribute: kAXValueAttribute)
        if currentValue == newValue { return false }
        return true
    }

    private func getStringValue(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value as? String
    }

    // MARK: - Strategy 2: CGEvent Cmd+V (Wispr Flow's approach)

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down: Cmd+V
        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: true
        )
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        usleep(10_000) // 10ms

        // Key up: Cmd+V
        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: false
        )
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}
