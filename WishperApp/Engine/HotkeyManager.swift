import Carbon
import Cocoa
import Foundation
import OSLog

/// Minimal fn-key detector via CGEventTap.
/// Only handles fn press/release (flagsChanged). Everything else uses KeyboardShortcuts.
/// Includes a watchdog timer that re-enables the tap if macOS disables it.
@MainActor
final class FnKeyDetector {
    private let logger = WishperLog.voicePipeline

    nonisolated(unsafe) var onFnDown: (() -> Void)?
    nonisolated(unsafe) var onFnUp: (() -> Void)?
    nonisolated(unsafe) var onEsc: (() -> Void)?

    nonisolated(unsafe) private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    nonisolated(unsafe) private var isFnDown = false
    private var watchdogTask: Task<Void, Never>?

    func start() {
        createTap()
        startWatchdog()
    }

    func stop() {
        watchdogTask?.cancel()
        watchdogTask = nil
        destroyTap()
    }

    // MARK: - Event Tap

    private func createTap() {
        destroyTap()

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
                let detector = Unmanaged<FnKeyDetector>.fromOpaque(refcon).takeUnretainedValue()
                detector.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("fn key event tap creation failed — check Accessibility permission")
            return
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("fn key detector started")
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
        isFnDown = false
    }

    // MARK: - Watchdog (re-enables tap if macOS disables it)

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, let tap = self.eventTap else { continue }

                if !CGEvent.tapIsEnabled(tap: tap) {
                    self.logger.warning("fn key tap was disabled — re-enabling")
                    CGEvent.tapEnable(tap: tap, enable: true)
                }

                // If tap was completely destroyed, recreate it
                if self.eventTap == nil {
                    self.logger.warning("fn key tap lost — recreating")
                    self.createTap()
                }
            }
        }
    }

    // MARK: - Event Handling

    nonisolated private func handleEvent(type: CGEventType, event: CGEvent) {
        // Re-enable tap immediately if system disabled it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        // Esc (keyDown) → cancel
        if type == .keyDown, keyCode == 53 {
            onEsc?()
            return
        }

        // fn key (flagsChanged, keyCode 63)
        guard type == .flagsChanged, keyCode == 63 else { return }

        let fnPressed = event.flags.contains(.maskSecondaryFn)
        guard fnPressed != isFnDown else { return } // dedup
        isFnDown = fnPressed

        if fnPressed {
            onFnDown?()
        } else {
            onFnUp?()
        }
    }
}
