import AppKit
import CoreGraphics
import Foundation

struct HotkeyPermissionState {
    let accessibilityGranted: Bool
    let inputMonitoringGranted: Bool

    var allGranted: Bool {
        accessibilityGranted && inputMonitoringGranted
    }
}

enum HotkeyPermissionGuide {
    static func currentState() -> HotkeyPermissionState {
        HotkeyPermissionState(
            accessibilityGranted: AXIsProcessTrusted(),
            inputMonitoringGranted: CGPreflightListenEventAccess()
        )
    }

    @MainActor
    static func openAccessibilityGuide() {
        openAccessibilitySettings()
    }

    @MainActor
    @discardableResult
    static func requestInputMonitoringAccess() -> Bool {
        let granted = CGRequestListenEventAccess()
        if !granted {
            openInputMonitoringSettings()
        }
        return granted
    }

    @MainActor
    static func openAccessibilitySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    @MainActor
    static func openInputMonitoringSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
