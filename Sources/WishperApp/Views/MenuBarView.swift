import SwiftUI

struct MenuBarMenu: View {
    @ObservedObject var appState: AppState

    var body: some View {
        // Status
        Button {
            // no action
        } label: {
            Label(appState.statusMessage, systemImage: statusIcon)
        }
        .disabled(true)

        Divider()

        // Paste last transcript
        Button("Paste last transcript") {
            if !appState.lastCleanedText.isEmpty {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(appState.lastCleanedText, forType: .string)
                // Try to paste
                let script = NSAppleScript(source: """
                    tell application "System Events"
                        keystroke "v" using command down
                    end tell
                """)
                script?.executeAndReturnError(nil)
            }
        }
        .keyboardShortcut("v", modifiers: [.control, .command])
        .disabled(appState.lastCleanedText.isEmpty)

        if !appState.lastCleanedText.isEmpty {
            Text(String(appState.lastCleanedText.prefix(40)) + (appState.lastCleanedText.count > 40 ? "..." : ""))
                .foregroundStyle(.secondary)
                .font(.caption)
        }

        Divider()

        // Toggles
        Toggle("LLM Cleanup", isOn: $appState.cleanupEnabled)
        Toggle("Sound Effects", isOn: $appState.soundsEnabled)

        Divider()

        // Model info
        Menu("Models") {
            Text("ASR: \(appState.selectedASRModel)")
            Text("LLM: \(appState.selectedLLMModel)")
            Divider()
            SettingsLink {
                Text("Change Models...")
            }
        }

        Menu("Hotkey Mode") {
            Picker("Mode", selection: $appState.hotkeyMode) {
                Text("Push to Talk").tag("push_to_talk")
                Text("Toggle").tag("toggle")
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        Divider()

        SettingsLink {
            Text("Settings...")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Wishper") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var statusIcon: String {
        if appState.isRecording { return "record.circle.fill" }
        if appState.isTranscribing { return "waveform" }
        if appState.isCleaning { return "sparkles" }
        return "checkmark.circle"
    }
}
