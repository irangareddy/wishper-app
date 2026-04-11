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
    var onCancel: (@Sendable () -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var mode: HotkeyMode = .pushToTalk
    private var isToggled = false
    private var isTargetKeyDown = false
    private var targetKeyCode: CGKeyCode = CGKeyCode(kVK_RightCommand)
    private var targetModifiers: NSEvent.ModifierFlags = []

    func configure(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags = []) {
        self.targetKeyCode = keyCode
        self.targetModifiers = modifiers
    }

    func start(
        mode: HotkeyMode = .pushToTalk,
        keyCode: CGKeyCode = CGKeyCode(kVK_RightCommand),
        modifiers: NSEvent.ModifierFlags = []
    ) {
        self.mode = mode
        self.targetKeyCode = keyCode
        self.targetModifiers = modifiers
        self.isTargetKeyDown = false

        let trusted = AXIsProcessTrusted()
        print("[wishper] AXIsProcessTrusted() = \(trusted)")

        if !trusted {
            // Only prompt if not already granted
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            print("[wishper] Accessibility not granted — prompting user.")
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
        print("[wishper] Hotkey event tap active for keyCode=\(targetKeyCode) modifiers=\(targetModifiers.rawValue)")
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
        let flags = normalizedModifierFlags(from: event.flags)
        print("[wishper] CGEvent: type=\(type.rawValue) keyCode=\(keyCode) flags=\(flags.rawValue) target=\(targetKeyCode) targetModifiers=\(targetModifiers.rawValue)")

        if type == .keyDown, keyCode == 53 {
            onCancel?()
            return
        }

        switch type {
        case .flagsChanged:
            guard isModifierOnlyHotkey, keyCode == targetKeyCode else { return }
            guard let modifierFlag = modifierFlag(for: keyCode) else { return }
            processTargetKeyTransition(
                isPressed: flags.contains(modifierFlag),
                source: "CGEvent"
            )
        case .keyDown:
            guard !isModifierOnlyHotkey, keyCode == targetKeyCode else { return }
            guard flags == normalizedTargetModifiers else { return }
            processTargetKeyTransition(isPressed: true, source: "CGEvent")
        case .keyUp:
            guard !isModifierOnlyHotkey, keyCode == targetKeyCode else { return }
            processTargetKeyTransition(isPressed: false, source: "CGEvent")
        default:
            return
        }
    }

    private func handleEvent(event: NSEvent) {
        let keyCode = CGKeyCode(event.keyCode)
        let modifiers = normalizedModifierFlags(from: event.modifierFlags)
        print("[wishper] NSEvent: type=\(event.type.rawValue) keyCode=\(keyCode) modifierFlags=\(modifiers.rawValue) target=\(targetKeyCode) targetModifiers=\(targetModifiers.rawValue)")

        if event.type == .keyDown, keyCode == 53 {
            onCancel?()
            return
        }

        switch event.type {
        case .flagsChanged:
            guard isModifierOnlyHotkey, keyCode == targetKeyCode else { return }
            guard let modifierFlag = modifierFlag(for: keyCode) else { return }
            processTargetKeyTransition(
                isPressed: modifiers.contains(modifierFlag),
                source: "NSEvent"
            )
        case .keyDown:
            guard !isModifierOnlyHotkey, keyCode == targetKeyCode else { return }
            guard modifiers == normalizedTargetModifiers else { return }
            processTargetKeyTransition(isPressed: true, source: "NSEvent")
        case .keyUp:
            guard !isModifierOnlyHotkey, keyCode == targetKeyCode else { return }
            processTargetKeyTransition(isPressed: false, source: "NSEvent")
        default:
            return
        }
    }

    private func processTargetKeyTransition(isPressed: Bool, source: String) {
        guard isPressed != isTargetKeyDown else {
            print("[wishper] \(source): ignoring duplicate hotkey state \(isPressed)")
            return
        }

        isTargetKeyDown = isPressed
        print("[wishper] \(source): hotkey \(isPressed ? "pressed" : "released")")

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

    private var isModifierOnlyHotkey: Bool {
        normalizedTargetModifiers.isEmpty && modifierFlag(for: targetKeyCode) != nil
    }

    private var normalizedTargetModifiers: NSEvent.ModifierFlags {
        normalizedModifierFlags(from: targetModifiers)
    }

    private func normalizedModifierFlags(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .control, .option, .shift, .function])
    }

    private func normalizedModifierFlags(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var modifiers: NSEvent.ModifierFlags = []

        if flags.contains(.maskCommand) {
            modifiers.insert(.command)
        }
        if flags.contains(.maskControl) {
            modifiers.insert(.control)
        }
        if flags.contains(.maskAlternate) {
            modifiers.insert(.option)
        }
        if flags.contains(.maskShift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.maskSecondaryFn) {
            modifiers.insert(.function)
        }

        return modifiers
    }

    private func modifierFlag(for keyCode: CGKeyCode) -> NSEvent.ModifierFlags? {
        switch Int(keyCode) {
        case Int(kVK_Command), Int(kVK_RightCommand):
            return .command
        case Int(kVK_Shift), Int(kVK_RightShift):
            return .shift
        case Int(kVK_Control), Int(kVK_RightControl):
            return .control
        case Int(kVK_Option), Int(kVK_RightOption):
            return .option
        case Int(kVK_Function):
            return .function
        default:
            return nil
        }
    }
}
