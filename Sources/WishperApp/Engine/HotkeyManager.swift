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
    private var globalMonitor: Any?
    private var mode: HotkeyMode = .pushToTalk
    private var isToggled = false
    private var isTargetKeyDown = false

    // Right Command key
    private let targetKeyCode = CGKeyCode(kVK_RightCommand)

    func start(mode: HotkeyMode = .pushToTalk) {
        self.mode = mode
        self.isTargetKeyDown = false

        let axTrusted = AXIsProcessTrusted()
        print("[wishper] AXIsProcessTrusted() = \(axTrusted)")
        print("[wishper] Hotkey target keyCode = \(targetKeyCode) (kVK_RightCommand = \(kVK_RightCommand))")

        // Request accessibility permission — shows system prompt if not trusted
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        print("[wishper] AXIsProcessTrustedWithOptions(prompt: true) = \(trusted)")
        if !trusted {
            print("[wishper] Accessibility permission not granted. A system dialog should appear.")
            print("[wishper] After granting, restart the app.")
        }

        // Try to create both monitors. NSEvent's global monitor is generally more reliable
        // for modifier keys in MenuBarExtra apps, while the event tap provides extra visibility.
        createEventTap()
        createGlobalMonitor()
    }

    private func createEventTap() {
        let eventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (
                proxy: CGEventTapProxy,
                type: CGEventType,
                event: CGEvent,
                refcon: UnsafeMutableRawPointer?
            ) -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[wishper] Failed to create event tap.")
            print("[wishper] Ensure this app has Accessibility permission in:")
            print("[wishper]   System Settings > Privacy & Security > Accessibility")
            return
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[wishper] CGEvent tap created: valid=\(CFMachPortIsValid(tap))")
        print("[wishper] CGEvent.tapEnable(tap, true) called")
        print("[wishper] Hotkey event tap active (Right Cmd)")
    }

    private func createGlobalMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .keyUp]
        ) { [weak self] event in
            self?.handleEvent(event: event)
        }

        if globalMonitor != nil {
            print("[wishper] NSEvent global monitor active for flagsChanged/keyDown/keyUp")
        } else {
            print("[wishper] Failed to create NSEvent global monitor")
        }
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
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        globalMonitor = nil
        isTargetKeyDown = false
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        // Handle tap being disabled by the system (e.g., timeout)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            print("[wishper] Event tap re-enabled after system disable")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                print("[wishper] CGEvent.tapEnable(tap, true) called after disable")
            }
            return
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        print("[wishper] CGEvent: type=\(type.rawValue) keyCode=\(keyCode) flags=\(flags.rawValue) target=\(targetKeyCode)")
        guard keyCode == targetKeyCode else { return }

        let isPressed = switch type {
        case .flagsChanged:
            flags.contains(.maskCommand)
        case .keyDown:
            true
        case .keyUp:
            false
        default:
            flags.contains(.maskCommand)
        }

        processTargetKeyTransition(isPressed: isPressed, source: "CGEvent")
    }

    private func handleEvent(event: NSEvent) {
        let keyCode = CGKeyCode(event.keyCode)
        print("[wishper] NSEvent: type=\(event.type.rawValue) keyCode=\(keyCode) modifierFlags=\(event.modifierFlags.rawValue) target=\(targetKeyCode)")
        guard keyCode == targetKeyCode else { return }

        let isPressed = switch event.type {
        case .flagsChanged:
            event.modifierFlags.contains(.command)
        case .keyDown:
            true
        case .keyUp:
            false
        default:
            event.modifierFlags.contains(.command)
        }

        processTargetKeyTransition(isPressed: isPressed, source: "NSEvent")
    }

    private func processTargetKeyTransition(isPressed: Bool, source: String) {
        guard isPressed != isTargetKeyDown else {
            print("[wishper] \(source): ignoring duplicate Right Command state \(isPressed)")
            return
        }

        isTargetKeyDown = isPressed
        print("[wishper] \(source): Right Command \(isPressed ? "pressed" : "released")")

        switch mode {
        case .pushToTalk:
            if isPressed {
                onRecordingStart?()
            } else {
                onRecordingStop?()
            }
        case .toggle:
            if isPressed {
                if isToggled {
                    isToggled = false
                    onRecordingStop?()
                } else {
                    isToggled = true
                    onRecordingStart?()
                }
            }
        }
    }
}
