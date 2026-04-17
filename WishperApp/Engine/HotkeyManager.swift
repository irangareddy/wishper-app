import Carbon
import Cocoa
import Foundation
import OSLog

/// Detects modifier-only key press/release (fn, Right Command, etc.) and Esc.
/// Uses CGEventTap (.listenOnly) on the main run loop.
/// Includes a watchdog timer that re-enables the tap if macOS disables it.
@MainActor
final class ModifierKeyDetector {
    private let logger = WishperLog.voicePipeline

    nonisolated(unsafe) var onPttDown: (() -> Void)?
    nonisolated(unsafe) var onPttUp: (() -> Void)?
    nonisolated(unsafe) var onCancel: (() -> Void)?

    // Configurable keys
    nonisolated(unsafe) var pttKeyCode: UInt16 = 63
    nonisolated(unsafe) var pttModifierFlag: NSEvent.ModifierFlags = .function
    nonisolated(unsafe) var cancelKeyCode: UInt16 = 53
    nonisolated(unsafe) var cancelUsesCmdPeriod = false

    nonisolated(unsafe) private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    nonisolated(unsafe) private var isPttDown = false
    private var watchdogTask: Task<Void, Never>?

    struct PermissionState {
        let accessibilityTrusted: Bool
        let inputMonitoringTrusted: Bool

        var fullyTrusted: Bool {
            accessibilityTrusted && inputMonitoringTrusted
        }
    }

    /// Map key name strings to (keyCode, modifierFlag)
    static let keyMap: [String: (keyCode: UInt16, flag: NSEvent.ModifierFlags)] = [
        "fn":           (63, .function),
        "rightCommand": (54, .command),
        "rightOption":  (61, .option),
        "rightControl": (62, .control),
        "rightShift":   (60, .shift),
    ]

    func configure(pttKey: String, cancelKey: String) {
        if let mapping = Self.keyMap[pttKey] {
            pttKeyCode = mapping.keyCode
            pttModifierFlag = mapping.flag
        }

        if cancelKey == "cmdPeriod" {
            cancelKeyCode = 47
            cancelUsesCmdPeriod = true
        } else if cancelKey == "fn" {
            cancelKeyCode = 63
            cancelUsesCmdPeriod = false
        } else {
            cancelKeyCode = 53
            cancelUsesCmdPeriod = false
        }

        logger.info("configured ptt=\(pttKey) cancel=\(cancelKey)")
    }

    func permissionState(prompt: Bool) -> PermissionState {
        let accessibilityTrusted: Bool
        if prompt {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        } else {
            accessibilityTrusted = AXIsProcessTrusted()
        }

        let inputMonitoringTrusted: Bool
        if prompt {
            inputMonitoringTrusted = CGRequestListenEventAccess()
        } else {
            inputMonitoringTrusted = CGPreflightListenEventAccess()
        }

        return PermissionState(
            accessibilityTrusted: accessibilityTrusted,
            inputMonitoringTrusted: inputMonitoringTrusted
        )
    }

    @discardableResult
    func start(promptForPermissions: Bool = true) -> Bool {
        let permissions = permissionState(prompt: promptForPermissions)
        logger.info(
            "starting modifier detector, accessibility=\(permissions.accessibilityTrusted) inputMonitoring=\(permissions.inputMonitoringTrusted)"
        )

        guard permissions.fullyTrusted else {
            if !permissions.accessibilityTrusted {
                logger.error("accessibility not granted; modifier detector not started")
            }
            if !permissions.inputMonitoringTrusted {
                logger.error("input monitoring not granted; modifier detector not started")
            }
            destroyTap()
            watchdogTask?.cancel()
            watchdogTask = nil
            return false
        }

        let tapCreated = createTap()
        startWatchdog()
        return tapCreated
    }

    func stop() {
        watchdogTask?.cancel()
        watchdogTask = nil
        destroyTap()
    }

    // MARK: - Event Tap

    private func createTap() -> Bool {
        guard eventTap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let detector = Unmanaged<ModifierKeyDetector>.fromOpaque(refcon).takeUnretainedValue()
                detector.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("event tap creation failed")
            return false
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("modifier key detector started")
        return true
    }

    private func destroyTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isPttDown = false
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self else { return }

                if let tap = self.eventTap {
                    if !CGEvent.tapIsEnabled(tap: tap) {
                        CGEvent.tapEnable(tap: tap, enable: true)
                        self.logger.info("watchdog re-enabled tap")
                    }
                } else {
                    self.logger.info("watchdog recreating tap")
                    if !self.createTap() {
                        self.logger.error("watchdog failed to recreate tap")
                    }
                }
            }
        }
    }

    // MARK: - Event Handling

    nonisolated private func handleEvent(type: CGEventType, event: CGEvent) {
        // Re-enable tap if system disabled it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        // Cancel: Esc or ⌘.
        if type == .keyDown {
            if cancelUsesCmdPeriod {
                let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                if keyCode == cancelKeyCode && flags.contains(.command) {
                    onCancel?()
                    return
                }
            } else if keyCode == cancelKeyCode {
                onCancel?()
                return
            }
        }

        // PTT modifier key (flagsChanged)
        guard type == .flagsChanged, keyCode == pttKeyCode else { return }

        let pressed = event.flags.contains(CGEventFlags(rawValue: UInt64(pttModifierFlag.rawValue)))
            || (pttKeyCode == 63 && event.flags.contains(.maskSecondaryFn))
            || (pttKeyCode == 54 && event.flags.contains(.maskCommand))
            || (pttKeyCode == 61 && event.flags.contains(.maskAlternate))
            || (pttKeyCode == 62 && event.flags.contains(.maskControl))
            || (pttKeyCode == 60 && event.flags.contains(.maskShift))

        guard pressed != isPttDown else { return }
        isPttDown = pressed

        if pressed {
            onPttDown?()
        } else {
            onPttUp?()
        }
    }
}
