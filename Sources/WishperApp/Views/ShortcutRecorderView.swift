import AppKit
import SwiftUI

struct ShortcutRecorderView: View {
    @Binding var configuration: HotkeyConfiguration

    @State private var isRecording = false
    @State private var draftConfiguration: HotkeyConfiguration?
    @State private var localMonitor: Any?
    @State private var isCursorVisible = true

    private let cursorTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleRecording) {
                HStack(spacing: 6) {
                    Text(displayText)
                        .monospacedDigit()
                    if isRecording {
                        Text(isCursorVisible ? "|" : " ")
                            .fontWeight(.medium)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minWidth: 160, alignment: .leading)
            }
            .buttonStyle(.bordered)

            if isRecording {
                Button("Confirm", action: confirmRecording)
                    .disabled(draftConfiguration == nil)
                Button("Cancel", action: cancelRecording)
            }
        }
        .onReceive(cursorTimer) { _ in
            guard isRecording else {
                isCursorVisible = true
                return
            }

            withAnimation(.easeInOut(duration: 0.2)) {
                isCursorVisible.toggle()
            }
        }
        .onDisappear {
            stopMonitoring()
        }
    }

    private var displayText: String {
        if let draftConfiguration {
            return draftConfiguration.displayString
        }

        if isRecording {
            return "Type shortcut"
        }

        return configuration.displayString
    }

    private func toggleRecording() {
        if isRecording {
            cancelRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        draftConfiguration = configuration
        isRecording = true
        isCursorVisible = true
        installMonitorIfNeeded()
    }

    private func confirmRecording() {
        guard let draftConfiguration else { return }
        configuration = draftConfiguration
        isRecording = false
        stopMonitoring()
    }

    private func cancelRecording() {
        draftConfiguration = nil
        isRecording = false
        isCursorVisible = true
        stopMonitoring()
    }

    private func installMonitorIfNeeded() {
        guard localMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event: event) ? nil : event
        }
    }

    private func stopMonitoring() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handle(event: NSEvent) -> Bool {
        guard isRecording else { return false }

        switch event.type {
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .keyDown:
            return handleKeyDown(event)
        default:
            return false
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case 54:
            draftConfiguration = .rightCommand
            return true
        case 55:
            draftConfiguration = HotkeyConfiguration(
                modifierFlagsRawValue: NSEvent.ModifierFlags.command.rawValue,
                keyCode: event.keyCode,
                keyChar: nil
            )
            return true
        case 63:
            draftConfiguration = .fn
            return true
        default:
            guard flags.isValidModifiers else {
                return false
            }

            draftConfiguration = HotkeyConfiguration(
                modifierFlagsRawValue: flags.rawValue,
                keyCode: 0,
                keyChar: nil
            )
            return true
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isValidModifiers else {
            return false
        }

        let keyChar = normalizedKeyCharacter(from: event)
        guard let keyChar else {
            return false
        }

        draftConfiguration = HotkeyConfiguration(
            modifierFlagsRawValue: flags.rawValue,
            keyCode: event.keyCode,
            keyChar: keyChar
        )
        return true
    }

    private func normalizedKeyCharacter(from event: NSEvent) -> String? {
        guard let characters = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !characters.isEmpty
        else {
            return nil
        }

        return String(characters.prefix(1)).uppercased()
    }
}

extension NSEvent.ModifierFlags {
    var isValidModifiers: Bool {
        !intersection([.command, .control, .option, .shift, .function]).isEmpty
    }
}
