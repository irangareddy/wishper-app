import SwiftUI

struct MenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var appState: AppState
    @State private var recordingStartedAt: Date?
    @State private var currentTime = Date()

    var body: some View {
        Button("Open Wishper") {
            openWindow(id: "main")
        }

        Section("Status") {
            statusRow(title: appState.statusMessage, systemImage: statusIcon)
            statusRow(title: "ASR: \(shortModelName(appState.selectedASRModel))", systemImage: "waveform")
            statusRow(title: "LLM: \(shortModelName(appState.selectedLLMModel))", systemImage: "sparkles")

            if appState.isRecording {
                statusRow(title: "Duration: \(recordingDurationText)", systemImage: "timer")
            }
        }

        Section("Actions") {
            Button {
                pasteLastTranscript()
            } label: {
                actionRow(title: "Paste Last Transcript", hint: "⌃⌘V")
            }
            .keyboardShortcut("v", modifiers: [.control, .command])
            .disabled(appState.lastCleanedText.isEmpty)

            SettingsLink {
                actionRow(title: "Settings…", hint: "⌘,")
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        if !appState.lastCleanedText.isEmpty {
            Section("Last Transcript") {
                Text(transcriptPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        Section("Preferences") {
            Toggle("LLM Cleanup", isOn: $appState.cleanupEnabled)
            Toggle("Sound Effects", isOn: $appState.soundsEnabled)

            Menu {
                statusRow(title: appState.selectedASRModel, systemImage: "waveform")
                statusRow(title: appState.selectedLLMModel, systemImage: "sparkles")
                Divider()
                SettingsLink {
                    Text("Change Models…")
                }
            } label: {
                Label("Models", systemImage: "cpu")
            }

            Menu {
                Picker("Mode", selection: $appState.hotkeyMode) {
                    Text("Push to Talk").tag("push_to_talk")
                    Text("Toggle").tag("toggle")
                }
                .pickerStyle(.inline)
            } label: {
                Label("Hotkey Mode", systemImage: "keyboard")
            }

            statusRow(title: "Shortcut: \(appState.hotkeyConfig.displayString)", systemImage: "command")
        }

        Section {
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                actionRow(title: "Quit Wishper", hint: "⌘Q")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .onAppear {
            if appState.isRecording, recordingStartedAt == nil {
                recordingStartedAt = Date()
            }
        }
        .onChange(of: appState.isRecording) { _, isRecording in
            recordingStartedAt = isRecording ? Date() : nil
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { newTime in
            currentTime = newTime
        }
    }

    private var statusIcon: String {
        if appState.isRecording { return "record.circle.fill" }
        if appState.isTranscribing { return "waveform" }
        if appState.isCleaning { return "sparkles" }
        return "checkmark.circle"
    }

    private var recordingDurationText: String {
        guard let recordingStartedAt else { return "0:00" }
        let duration = Int(currentTime.timeIntervalSince(recordingStartedAt))
        let minutes = duration / 60
        let seconds = duration % 60
        return "\(minutes):" + String(format: "%02d", seconds)
    }

    private var transcriptPreview: String {
        let transcript = appState.lastCleanedText
        if transcript.count <= 90 { return transcript }
        return String(transcript.prefix(90)) + "…"
    }

    private func shortModelName(_ model: String) -> String {
        model.split(separator: "/").last.map(String.init) ?? model
    }

    private func pasteLastTranscript() {
        guard !appState.lastCleanedText.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(appState.lastCleanedText, forType: .string)

        let script = NSAppleScript(source: """
            tell application "System Events"
                keystroke "v" using command down
            end tell
        """)
        script?.executeAndReturnError(nil)
    }

    private func statusRow(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .disabled(true)
    }

    private func actionRow(title: String, hint: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 16)
            Text(hint)
                .foregroundStyle(.secondary)
        }
    }
}
