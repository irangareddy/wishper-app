@preconcurrency import ApplicationServices
import Cocoa
import Foundation
import OSLog

// MARK: - Accessibility Permission Manager

nonisolated final class AccessibilityPermissionManager {
    var onPermissionChange: (() -> Void)?

    private var cancellable: Any?

    static func isGranted() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as NSDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as NSDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    init() {
        self.cancellable = NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onPermissionChange?()
        }
    }

    deinit {
        if let observer = cancellable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: - Fn Key Detector

/// Detects fn key press/release and Esc via CGEventTap (.defaultTap).
/// Uses Input Monitoring permission (lighter than full Accessibility).
/// Watches for permission changes and auto-reconnects.
nonisolated final class FnKeyDetector: @unchecked Sendable {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "in.irangareddy.Wishper-App",
        category: "hotkeys"
    )

    var onFnDown: (() -> Void)?
    var onFnUp: (() -> Void)?
    var onEsc: (() -> Void)?

    private var eventTap: CFMachPort?
    private var isFnDown = false
    private let permissionManager = AccessibilityPermissionManager()

    func start() {
        permissionManager.onPermissionChange = { [weak self] in
            // Small delay for system database to update
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let self else { return }
                if AccessibilityPermissionManager.isGranted() {
                    self.logger.info("permission granted — starting tap")
                    self.createTap()
                } else {
                    self.logger.warning("permission revoked — removing tap")
                    self.destroyTap()
                }
            }
        }

        if AccessibilityPermissionManager.isGranted() {
            createTap()
        } else {
            logger.warning("accessibility not granted — requesting")
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
            let detector = Unmanaged<FnKeyDetector>.fromOpaque(refcon).takeUnretainedValue()
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
            logger.error("failed to create event tap — check Input Monitoring permission")
            return
        }

        self.eventTap = tap

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        logger.info("fn key detector started (.defaultTap)")
    }

    private func destroyTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        eventTap = nil
        isFnDown = false
    }

    // MARK: - Event Handling

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if system disabled it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                logger.info("tap re-enabled after system disable")
            }
            return Unmanaged.passUnretained(event)
        }

        // Convert to NSEvent for cleaner processing
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = nsEvent.keyCode

        // Esc (keyDown) → cancel
        if nsEvent.type == .keyDown, keyCode == 53 {
            onEsc?()
            // Return event so Esc still works in other apps
            return Unmanaged.passUnretained(event)
        }

        // fn key (flagsChanged, keyCode 63)
        guard nsEvent.type == .flagsChanged, keyCode == 63 else {
            return Unmanaged.passUnretained(event)
        }

        let fnPressed = nsEvent.modifierFlags.contains(.function)
        guard fnPressed != isFnDown else {
            return Unmanaged.passUnretained(event)
        }
        isFnDown = fnPressed

        if fnPressed {
            onFnDown?()
        } else {
            onFnUp?()
        }

        // Return event so fn still works for other apps
        return Unmanaged.passUnretained(event)
    }
}
