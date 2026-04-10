import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status header
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(appState.statusMessage)
                    .font(.headline)
                Spacer()
            }
            
            Divider()
            
            // Last transcription
            if !appState.lastCleanedText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last transcription")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appState.lastCleanedText)
                        .font(.body)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }
            
            Divider()
            
            // Controls
            Toggle("LLM Cleanup", isOn: $appState.cleanupEnabled)
            Toggle("Sounds", isOn: $appState.soundsEnabled)
            
            Divider()
            
            // Footer
            HStack {
                SettingsLink {
                    Text("Settings...")
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding()
        .frame(width: 300)
    }
    
    private var statusColor: Color {
        if appState.isRecording { return .red }
        if appState.isTranscribing || appState.isCleaning { return .orange }
        return .green
    }
}
