import AppKit
import SwiftUI

/// A shortcut recorder that looks like KeyboardShortcuts.Recorder
/// but supports modifier-only keys (fn, Right Command, etc.)
struct ShortcutRecorderView: View {
    @Binding var configuration: HotkeyConfiguration

    @State private var isRecording = false
    @State private var localMonitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            // Main button
            Button(action: toggleRecording) {
                Text(displayText)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(isRecording ? .primary : .secondary)
                    .frame(minWidth: 80, alignment: .center)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)

            // Clear button
            if !isRecording && configuration.keyCode != 0 || configuration.modifierFlagsRawValue != 0 {
                Button {
                    configuration = HotkeyConfiguration(modifierFlagsRawValue: 0, keyCode: 0, keyChar: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .onDisappear { stopMonitoring() }
    }

    private var displayText: String {
        if isRecording {
            return "Record Shortcut"
        }
        let sym = configuration.symbolString
        return sym == "None" ? "Record Shortcut" : sym
    }

    private func toggleRecording() {
        if isRecording {
            stopMonitoring()
            isRecording = false
        } else {
            isRecording = true
            installMonitor()
        }
    }

    private func installMonitor() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if handleEvent(event) { return nil }
            return event
        }
    }

    private func stopMonitoring() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleEvent(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }

        // Esc cancels recording
        if event.type == .keyDown && event.keyCode == 53 {
            isRecording = false
            stopMonitoring()
            return true
        }

        switch event.type {
        case .flagsChanged:
            return handleFlags(event)
        case .keyDown:
            return handleKeyDown(event)
        default:
            return false
        }
    }

    private func handleFlags(_ event: NSEvent) -> Bool {
        // Modifier-only keys: fn, Right Command, Left Command
        switch event.keyCode {
        case 54: // Right Command
            accept(.rightCommand)
            return true
        case 55: // Left Command
            accept(HotkeyConfiguration(modifierFlagsRawValue: NSEvent.ModifierFlags.command.rawValue, keyCode: 55, keyChar: nil))
            return true
        case 63: // fn
            accept(.fn)
            return true
        default:
            return false
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isValidModifiers else { return false }

        guard let chars = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines),
              !chars.isEmpty else { return false }

        let keyChar = String(chars.prefix(1)).uppercased()
        accept(HotkeyConfiguration(
            modifierFlagsRawValue: flags.rawValue,
            keyCode: event.keyCode,
            keyChar: keyChar
        ))
        return true
    }

    private func accept(_ config: HotkeyConfiguration) {
        configuration = config
        isRecording = false
        stopMonitoring()
    }
}

extension NSEvent.ModifierFlags {
    var isValidModifiers: Bool {
        !intersection([.command, .control, .option, .shift, .function]).isEmpty
    }
}
