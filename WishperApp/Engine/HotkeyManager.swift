import Carbon
import Cocoa
import Foundation
import OSLog

/// Minimal fn-key detector via CGEventTap.
/// Only handles fn press/release (flagsChanged). Everything else uses KeyboardShortcuts.
@MainActor
final class FnKeyDetector {
    private let logger = WishperLog.voicePipeline

    nonisolated(unsafe) var onFnDown: (() -> Void)?
    nonisolated(unsafe) var onFnUp: (() -> Void)?
    nonisolated(unsafe) var onEsc: (() -> Void)?

    nonisolated(unsafe) private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    nonisolated(unsafe) private var isFnDown = false

    func start() {
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
            logger.error("fn key event tap creation failed")
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

    func stop() {
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
