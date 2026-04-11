@preconcurrency import ApplicationServices
import AppKit
import Carbon
import Foundation
import OSLog

@MainActor
final class TextInjector {
    private let logger = WishperLog.voicePipeline

    private static let textElementRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
    ]

    /// Inject text into the target app. Pass the target app's PID to bypass focus issues.
    func inject(_ text: String, targetPID: pid_t? = nil) -> Bool {
        // Always put text on clipboard first
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Strategy 1: Accessibility API — direct insert at cursor
        if insertViaAccessibility(text) {
            logger.info("injection path=accessibility")
            return true
        }

        // Strategy 2: postToPid — delivers Cmd+V directly to target process, bypasses focus
        if let pid = targetPID {
            simulatePasteToPID(pid)
            logger.info("injection path=postToPid pid=\(pid)")
            return true
        }

        // Strategy 3: Post to session (fallback if no PID)
        simulatePaste()
        logger.info("injection path=sessionPaste")
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

    // MARK: - Strategy 2: postToPid (bypasses focus entirely)

    private func simulatePasteToPID(_ pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: true
        )
        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: false
        )

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        // Deliver directly to target process — skips window server focus check
        keyDown?.postToPid(pid)
        usleep(10_000) // 10ms
        keyUp?.postToPid(pid)
    }

    // MARK: - Strategy 3: Post to session (fallback)

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: true
        )
        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: false
        )

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        usleep(10_000)
        keyUp?.post(tap: .cghidEventTap)
    }
}
