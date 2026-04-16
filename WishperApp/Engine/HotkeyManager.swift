@preconcurrency import ApplicationServices
import Carbon
import Cocoa
import Foundation
import OSLog

// MARK: - Accessibility Permission Manager

nonisolated final class AccessibilityPermissionManager {
    var onPermissionChange: (() -> Void)?

    private var observer: Any?

    static func isGranted() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as NSDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as NSDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    init() {
        self.observer = NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onPermissionChange?()
        }
    }

    deinit {
        if let obs = observer { NotificationCenter.default.removeObserver(obs) }
    }
}

// MARK: - Modifier Key Detector

/// Detects modifier-only key press/release (fn, Right Command, etc.) and Esc.
/// Uses CGEventTap (.defaultTap) with NSEvent conversion.
/// Supports configurable PTT key and cancel key.
nonisolated final class ModifierKeyDetector: @unchecked Sendable {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "in.irangareddy.Wishper-App",
        category: "hotkeys"
    )

    // Callbacks
    var onPttDown: (() -> Void)?
    var onPttUp: (() -> Void)?
    var onCancel: (() -> Void)?

    // Configurable keys
    var pttKeyCode: UInt16 = 63           // fn
    var pttModifierFlag: NSEvent.ModifierFlags = .function
    var cancelKeyCode: UInt16 = 53        // Esc
    var cancelUsesCmdPeriod = false        // ⌘. mode

    private var eventTap: CFMachPort?
    private var isPttDown = false
    private let permissionManager = AccessibilityPermissionManager()

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
            cancelKeyCode = 47 // kVK_ANSI_Period
            cancelUsesCmdPeriod = true
        } else if cancelKey == "fn" {
            // fn as cancel — handled separately via flagsChanged
            cancelKeyCode = 63
            cancelUsesCmdPeriod = false
        } else {
            cancelKeyCode = 53 // Esc
            cancelUsesCmdPeriod = false
        }

        logger.info("configured ptt=\(pttKey) cancel=\(cancelKey)")
    }

    func start() {
        permissionManager.onPermissionChange = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let self else { return }
                if AccessibilityPermissionManager.isGranted() {
                    self.createTap()
                } else {
                    self.destroyTap()
                }
            }
        }

        if AccessibilityPermissionManager.isGranted() {
            createTap()
        } else {
            AccessibilityPermissionManager.requestPermission()
        }
    }

    func stop() {
        destroyTap()
        permissionManager.onPermissionChange = nil
    }

    // MARK: - Event Tap

    private func createTap() {
        guard eventTap == nil else { return }

        let eventMask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)
        )

        let callback: CGEventTapCallBack = { (proxy, type, event, refcon) in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let detector = Unmanaged<ModifierKeyDetector>.fromOpaque(refcon).takeUnretainedValue()
            return detector.handleEvent(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("failed to create event tap")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("modifier key detector started")
    }

    private func destroyTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        eventTap = nil
        isPttDown = false
    }

    // MARK: - Event Handling

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable if system disabled
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }

        // Cancel: Esc key or ⌘.
        if nsEvent.type == .keyDown {
            if cancelUsesCmdPeriod {
                if nsEvent.keyCode == 47 && nsEvent.modifierFlags.contains(.command) {
                    onCancel?()
                    return Unmanaged.passUnretained(event)
                }
            } else if nsEvent.keyCode == cancelKeyCode {
                onCancel?()
                return Unmanaged.passUnretained(event)
            }
        }

        // PTT modifier key (flagsChanged)
        guard nsEvent.type == .flagsChanged, nsEvent.keyCode == pttKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        let pressed = nsEvent.modifierFlags.contains(pttModifierFlag)
        guard pressed != isPttDown else {
            return Unmanaged.passUnretained(event)
        }
        isPttDown = pressed

        if pressed {
            onPttDown?()
        } else {
            onPttUp?()
        }

        return Unmanaged.passUnretained(event)
    }
}
