import Carbon
import Cocoa
import Foundation

final class HotkeyManager {
    enum HotkeyMode {
        case pushToTalk
        case toggle
    }

    var onRecordingStart: (@Sendable () -> Void)?
    var onRecordingStop: (@Sendable () -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var mode: HotkeyMode = .pushToTalk
    private var isToggled = false

    // Right Command key
    private let targetKeyCode: CGKeyCode = 54  // kVK_RightCommand

    func start(mode: HotkeyMode = .pushToTalk) {
        self.mode = mode

        let eventMask = (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (
                proxy: CGEventTapProxy,
                type: CGEventType,
                event: CGEvent,
                refcon: UnsafeMutableRawPointer?
            ) -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[wishper] Failed to create event tap. Grant Accessibility permission.")
            return
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
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
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == targetKeyCode else {
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags
        let rightCmdPressed = flags.contains(.maskCommand) && keyCode == targetKeyCode

        switch mode {
        case .pushToTalk:
            if rightCmdPressed {
                onRecordingStart?()
            } else {
                onRecordingStop?()
            }
        case .toggle:
            if rightCmdPressed {
                if isToggled {
                    isToggled = false
                    onRecordingStop?()
                } else {
                    isToggled = true
                    onRecordingStart?()
                }
            }
        }

        return Unmanaged.passRetained(event)
    }
}
