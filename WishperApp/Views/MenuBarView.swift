import AppKit
import Combine
import SwiftUI

struct MenuBarMenu: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var updater = UpdaterManager.shared
    var onOpenWindow: () -> Void = {}
    @State private var currentTime = Date()
    @State private var injector = TextInjector()

    var body: some View {
        // Primary actions
        Button("Show Wishper") {
            onOpenWindow()
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        // Status
        Label(appState.statusMessage, systemImage: statusIcon)
            .disabled(true)

        if appState.isRecording {
            Label("Recording: \(recordingDurationText)", systemImage: "timer")
                .disabled(true)
            Text("Press Esc to cancel")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Divider()

        // Paste last transcript
        Button("Paste Last Transcript") {
            pasteLastTranscript()
        }
        .keyboardShortcut("v", modifiers: [.control, .command])
        .disabled(appState.lastCleanedText.isEmpty)

        if !appState.lastCleanedText.isEmpty {
            Text(transcriptPreview)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Divider()

        // Quick toggles
        Toggle("LLM Cleanup", isOn: $appState.cleanupEnabled)
        Toggle("Sounds", isOn: $appState.soundsEnabled)

        Divider()

        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)

        Divider()

        // Quit
        Button("Quit Wishper") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    // MARK: - Computed

    private var statusIcon: String {
        if appState.isRecording { return "record.circle.fill" }
        if appState.isTranscribing { return "waveform" }
        if appState.isCleaning { return "sparkles" }
        return "checkmark.circle"
    }

    private var recordingDurationText: String {
        guard let started = appState.recordingStartedAt else { return "0:00" }
        let seconds = Int(currentTime.timeIntervalSince(started))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private var transcriptPreview: String {
        let text = appState.lastCleanedText
        return text.count <= 80 ? text : String(text.prefix(80)) + "…"
    }

    private func pasteLastTranscript() {
        guard !appState.lastCleanedText.isEmpty else { return }
        let targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        _ = injector.inject(appState.lastCleanedText, targetPID: targetPID)
    }
}

// MARK: - Timer for recording duration
extension MenuBarMenu {
    func onTimerTick() -> some View {
        self.onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { time in
            currentTime = time
        }
    }
}
