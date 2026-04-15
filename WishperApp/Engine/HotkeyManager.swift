import Carbon
import Cocoa
import Foundation
import OSLog

@MainActor
final class HotkeyManager {
    private let logger = WishperLog.voicePipeline

    enum HotkeyMode {
        case pushToTalk
        case toggle
    }

    // MARK: - Callbacks

    var onRecordingStart: (() -> Void)?
    var onRecordingStop: (() -> Void)?
    var onCancel: (() -> Void)?
    /// Called when hands-free toggle activates (start or stop).
    var onHandsFreeToggle: ((_ startRecording: Bool) -> Void)?

    // MARK: - State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?

    // Push-to-talk config
    private var pttKeyCode: CGKeyCode = CGKeyCode(kVK_RightCommand)
    private var pttModifiers: NSEvent.ModifierFlags = []

    // Hands-free toggle config (nil = disabled)
    private var handsFreeKeyCode: CGKeyCode?
    private var handsFreeModifiers: NSEvent.ModifierFlags = []

    // Dual-mode state machine
    private var isPttKeyDown = false
    private var isHandsFreeActive = false
    private var pendingPttStart: Task<Void, Never>?
    private var comboWindowOpen = false

    /// Disambiguation window: how long to wait after the PTT key goes down
    /// before committing to push-to-talk (allows the combo key to arrive).
    private let comboWindowDuration: UInt64 = 150_000_000 // 150ms in nanoseconds

    // MARK: - Configuration

    /// Start with push-to-talk only (backward compatible).
    func start(
        mode: HotkeyMode = .pushToTalk,
        keyCode: CGKeyCode = CGKeyCode(kVK_RightCommand),
        modifiers: NSEvent.ModifierFlags = []
    ) {
        self.pttKeyCode = keyCode
        self.pttModifiers = modifiers
        self.handsFreeKeyCode = nil
        self.isPttKeyDown = false
        self.isHandsFreeActive = false
        setup()
    }

    /// Start with dual mode: push-to-talk + hands-free toggle on separate hotkeys.
    func startDualMode(
        pttKeyCode: CGKeyCode,
        pttModifiers: NSEvent.ModifierFlags = [],
        handsFreeKeyCode: CGKeyCode,
        handsFreeModifiers: NSEvent.ModifierFlags
    ) {
        self.pttKeyCode = pttKeyCode
        self.pttModifiers = pttModifiers
        self.handsFreeKeyCode = handsFreeKeyCode
        self.handsFreeModifiers = handsFreeModifiers
        self.isPttKeyDown = false
        self.isHandsFreeActive = false
        setup()
    }

    private func setup() {
        let trusted = AXIsProcessTrusted()
        logger.info("hotkey monitor starting accessibilityTrusted=\(trusted)")

        if !trusted {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            logger.info("accessibility prompt requested")
        }

        createEventTap()
        createGlobalMonitor()
    }

    func stop() {
        pendingPttStart?.cancel()
        pendingPttStart = nil
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
        isPttKeyDown = false
        isHandsFreeActive = false
    }

    // MARK: - Event Tap

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
                manager.handleCGEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("event tap creation failed")
            return
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("event tap active")
    }

    private func createGlobalMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .keyUp]
        ) { [weak self] event in
            self?.handleNSEvent(event: event)
        }

        if globalMonitor != nil {
            logger.info("global hotkey monitor active")
        } else {
            logger.error("global hotkey monitor creation failed")
        }
    }

    // MARK: - Event Handling

    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logger.debug("event tap re-enabled after system disable")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = normalizedModifierFlags(from: event.flags)

        processEvent(type: type, keyCode: keyCode, flags: flags, source: "CGEvent")
    }

    private func handleNSEvent(event: NSEvent) {
        let keyCode = CGKeyCode(event.keyCode)
        let flags = normalizedModifierFlags(from: event.modifierFlags)

        let type: CGEventType
        switch event.type {
        case .flagsChanged: type = .flagsChanged
        case .keyDown: type = .keyDown
        case .keyUp: type = .keyUp
        default: return
        }

        processEvent(type: type, keyCode: keyCode, flags: flags, source: "NSEvent")
    }

    private func processEvent(type: CGEventType, keyCode: CGKeyCode, flags: NSEvent.ModifierFlags, source: String) {
        // Esc always cancels
        if type == .keyDown, keyCode == 53 {
            cancelAll()
            return
        }

        let isDualMode = handsFreeKeyCode != nil

        if isDualMode {
            processDualMode(type: type, keyCode: keyCode, flags: flags, source: source)
        } else {
            processSingleMode(type: type, keyCode: keyCode, flags: flags, source: source)
        }
    }

    // MARK: - Single Mode (backward compatible)

    private func processSingleMode(type: CGEventType, keyCode: CGKeyCode, flags: NSEvent.ModifierFlags, source: String) {
        switch type {
        case .flagsChanged:
            guard isPttModifierOnly, keyCode == pttKeyCode else { return }
            guard let modifierFlag = modifierFlag(for: keyCode) else { return }
            processPttTransition(isPressed: flags.contains(modifierFlag), source: source)
        case .keyDown:
            guard !isPttModifierOnly, keyCode == pttKeyCode else { return }
            guard flags == normalizedPttModifiers else { return }
            processPttTransition(isPressed: true, source: source)
        case .keyUp:
            guard !isPttModifierOnly, keyCode == pttKeyCode else { return }
            processPttTransition(isPressed: false, source: source)
        default:
            return
        }
    }

    private func processPttTransition(isPressed: Bool, source: String) {
        guard isPressed != isPttKeyDown else { return }
        isPttKeyDown = isPressed
        logger.info("ptt \(isPressed ? "pressed" : "released", privacy: .public) source=\(source, privacy: .public)")

        if isPressed {
            onRecordingStart?()
        } else {
            onRecordingStop?()
        }
    }

    // MARK: - Dual Mode

    /// In dual mode:
    /// - PTT key alone (hold) → push-to-talk
    /// - PTT key + combo key → hands-free toggle
    /// - PTT key while hands-free is active → stop hands-free
    private func processDualMode(type: CGEventType, keyCode: CGKeyCode, flags: NSEvent.ModifierFlags, source: String) {
        guard let hfKeyCode = handsFreeKeyCode else { return }

        // Check if this is the hands-free combo key (e.g., Space with Fn modifier)
        if type == .keyDown, keyCode == hfKeyCode, flags == handsFreeModifiers {
            // Hands-free combo detected
            pendingPttStart?.cancel()
            pendingPttStart = nil
            comboWindowOpen = false

            if isHandsFreeActive {
                // Stop hands-free recording
                isHandsFreeActive = false
                logger.info("hands-free stopped via combo source=\(source, privacy: .public)")
                onHandsFreeToggle?(false)
            } else {
                // Start hands-free recording
                // If PTT already started a recording, it seamlessly becomes hands-free
                isHandsFreeActive = true
                if !isPttKeyDown {
                    // PTT wasn't held — start fresh
                    logger.info("hands-free started via combo source=\(source, privacy: .public)")
                    onHandsFreeToggle?(true)
                } else {
                    // PTT was held — recording already started, just upgrade to hands-free
                    logger.info("hands-free upgraded from ptt source=\(source, privacy: .public)")
                }
            }
            return
        }

        // Handle PTT key (modifier-only key like Fn)
        let isPttEvent: Bool
        let pttPressed: Bool

        if isPttModifierOnly {
            guard type == .flagsChanged, keyCode == pttKeyCode else { return }
            guard let modFlag = modifierFlag(for: keyCode) else { return }
            isPttEvent = true
            pttPressed = flags.contains(modFlag)
        } else {
            guard keyCode == pttKeyCode else { return }
            if type == .keyDown {
                guard flags == normalizedPttModifiers else { return }
                isPttEvent = true
                pttPressed = true
            } else if type == .keyUp {
                isPttEvent = true
                pttPressed = false
            } else {
                return
            }
        }

        guard isPttEvent, pttPressed != isPttKeyDown else { return }
        isPttKeyDown = pttPressed

        if pttPressed {
            if isHandsFreeActive {
                // PTT key pressed while hands-free is active → stop hands-free
                isHandsFreeActive = false
                logger.info("hands-free stopped via ptt key source=\(source, privacy: .public)")
                onHandsFreeToggle?(false)
            } else {
                // PTT key down — wait for combo window before committing to push-to-talk
                comboWindowOpen = true
                pendingPttStart?.cancel()
                pendingPttStart = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: self?.comboWindowDuration ?? 150_000_000)
                    guard let self, self.comboWindowOpen, !Task.isCancelled else { return }
                    self.comboWindowOpen = false
                    self.logger.info("ptt started (combo window expired) source=\(source, privacy: .public)")
                    self.onRecordingStart?()
                }
            }
        } else {
            // PTT key released
            if comboWindowOpen {
                // Released before combo window expired — very short press
                // Still treat as push-to-talk: start + immediate stop
                pendingPttStart?.cancel()
                pendingPttStart = nil
                comboWindowOpen = false
                // Too short to be useful — ignore
                logger.debug("ptt key released during combo window — ignored")
            } else if !isHandsFreeActive {
                // Normal PTT release → stop recording
                logger.info("ptt released source=\(source, privacy: .public)")
                onRecordingStop?()
            }
            // If hands-free is active, PTT release is ignored (hands-free keeps going)
        }
    }

    private func cancelAll() {
        pendingPttStart?.cancel()
        pendingPttStart = nil
        comboWindowOpen = false
        isHandsFreeActive = false
        isPttKeyDown = false
        onCancel?()
    }

    // MARK: - Helpers

    private var isPttModifierOnly: Bool {
        normalizedPttModifiers.isEmpty && modifierFlag(for: pttKeyCode) != nil
    }

    private var normalizedPttModifiers: NSEvent.ModifierFlags {
        normalizedModifierFlags(from: pttModifiers)
    }

    private func normalizedModifierFlags(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .control, .option, .shift, .function])
    }

    private func normalizedModifierFlags(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskSecondaryFn) { modifiers.insert(.function) }
        return modifiers
    }

    private func modifierFlag(for keyCode: CGKeyCode) -> NSEvent.ModifierFlags? {
        switch Int(keyCode) {
        case Int(kVK_Command), Int(kVK_RightCommand): return .command
        case Int(kVK_Shift), Int(kVK_RightShift): return .shift
        case Int(kVK_Control), Int(kVK_RightControl): return .control
        case Int(kVK_Option), Int(kVK_RightOption): return .option
        case Int(kVK_Function): return .function
        default: return nil
        }
    }
}
