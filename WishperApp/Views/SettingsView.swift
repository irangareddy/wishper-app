import ServiceManagement
import SwiftUI

// MARK: - Settings Detail View (single scroll, Gemini-style)

struct SettingsDetailView: View {
    @ObservedObject var appState: AppState
    @AppStorage("launchAtLoginEnabled") private var launchAtLoginEnabled = false
    @State private var launchAtLoginError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                // Sections
                settingsSection("Transcription", description: "Configure speech recognition language and text cleanup.") {
                    pickerRow("Language", selection: $appState.transcriptionLanguage) {
                        Text("English").tag("en")
                        Text("Chinese").tag("zh")
                        Text("Japanese").tag("ja")
                        Text("Korean").tag("ko")
                        Text("French").tag("fr")
                        Text("German").tag("de")
                        Text("Spanish").tag("es")
                        Divider()
                        Text("Auto-detect").tag("")
                    }
                    toggleRow("Clean up with LLM", isOn: $appState.cleanupEnabled)
                }

                settingsSection("Shortcuts", description: "Keyboard shortcuts for recording and pasting.") {
                    labeledRow("Push to talk") {
                        ShortcutRecorderView(configuration: $appState.hotkeyConfig)
                    }
                    pickerRow("Hands-free mode", selection: handsFreeBinding) {
                        Text("Fn + Space").tag(HotkeyConfiguration.fnSpace)
                        Text("Shift + Cmd + Space").tag(HotkeyConfiguration.shiftCommandSpace)
                    }
                    labeledRow("Paste last transcript") {
                        Text("⌃ ⌘ V")
                            .font(.caption)
                            .fontWeight(.medium)
                            .fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    }
                }

                settingsSection("Appearance") {
                    pickerRow("Chip position", selection: chipPositionBinding) {
                        ForEach(ChipPosition.allCases) { position in
                            Text(position.rawValue).tag(position)
                        }
                    }
                    toggleRow("Play sounds", isOn: $appState.soundsEnabled)
                }

                settingsSection("Models", description: "On-device ML models for speech recognition and text cleanup.") {
                    pickerRow("ASR model", selection: $appState.selectedASRModel) {
                        Text("Qwen3-ASR 0.6B").tag("aufklarer/Qwen3-ASR-0.6B-MLX-4bit")
                        Text("Whisper Tiny").tag("mlx-community/whisper-tiny")
                        Text("Whisper Large v3 Turbo").tag("mlx-community/whisper-large-v3-turbo")
                    }
                    pickerRow("LLM model", selection: $appState.selectedLLMModel) {
                        Text("Qwen3 0.6B 4-bit").tag("mlx-community/Qwen3-0.6B-4bit")
                        Text("Qwen3 1.7B 4-bit").tag("mlx-community/Qwen3-1.7B-4bit")
                        Text("Gemma 3 1B 4-bit").tag("mlx-community/gemma-3-1b-it-qat-4bit")
                        Text("Llama 3.2 1B 4-bit").tag("mlx-community/Llama-3.2-1B-Instruct-4bit")
                    }
                    labeledRow("Estimated latency") {
                        Text(performanceEstimate)
                            .foregroundStyle(.secondary)
                    }
                }

                settingsSection("System") {
                    toggleRow("Launch at login", isOn: launchAtLoginBinding)
                    if let launchAtLoginError {
                        Text(launchAtLoginError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 24)
                    }
                }

                if let monitor = appState.memoryMonitor {
                    settingsSection("Memory", description: "Runtime memory and model cache diagnostics.") {
                        labeledRow("Process resident") {
                            Text("\(monitor.currentResidentMB) MB").monospacedDigit().foregroundStyle(.secondary)
                        }
                        labeledRow("MLX active") {
                            Text("\(monitor.mlxActiveMemoryMB) MB").monospacedDigit().foregroundStyle(.secondary)
                        }
                        labeledRow("MLX cache") {
                            Text("\(monitor.mlxCacheMemoryMB) MB").monospacedDigit().foregroundStyle(.secondary)
                        }
                        labeledRow("Memory pressure") {
                            Text(monitor.pressureLevel.displayString)
                                .foregroundStyle(monitor.pressureLevel == .nominal ? .green : .orange)
                        }
                        labeledRow("ASR model") {
                            Circle().fill(monitor.asrModelLoaded ? .green : .gray).frame(width: 8, height: 8)
                            Text(monitor.asrModelLoaded ? "Loaded" : "Unloaded").foregroundStyle(.secondary)
                        }
                        labeledRow("LLM model") {
                            Circle().fill(monitor.llmModelLoaded ? .green : .gray).frame(width: 8, height: 8)
                            Text(monitor.llmModelLoaded ? "Loaded" : "Unloaded").foregroundStyle(.secondary)
                        }
                    }
                }

                settingsSection("About") {
                    labeledRow("Version") {
                        Text("0.3.0").foregroundStyle(.secondary)
                    }
                    labeledRow("Engine") {
                        Text("MLX on Apple Silicon").foregroundStyle(.secondary)
                    }
                    labeledRow("Privacy") {
                        Text("All processing on-device").foregroundStyle(.secondary)
                    }
                    linkRow("GitHub", url: "https://github.com/irangareddy/wishper-app")
                    linkRow("MLX Swift", url: "https://github.com/ml-explore/mlx-swift-lm")
                    linkRow("speech-swift", url: "https://github.com/soniqo/speech-swift")
                }

                Spacer(minLength: 24)
            }
        }
        .onAppear(perform: syncLaunchAtLoginState)
    }

    // MARK: - Section Builder

    private func settingsSection<Content: View>(
        _ title: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 10)

            // Section rows
            content()

            Divider()
                .padding(.top, 6)
        }
    }

    // MARK: - Row Builders

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
    }

    private func pickerRow<SelectionValue: Hashable, Content: View>(
        _ label: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(label)
            Spacer()
            Picker("", selection: selection, content: content)
                .labelsHidden()
                .frame(maxWidth: 200)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
    }

    private func labeledRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
            Spacer()
            content()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
    }

    private func linkRow(_ label: String, url: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Link(destination: URL(string: url)!) {
                HStack(spacing: 4) {
                    Text("Open")
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
    }

    // MARK: - Bindings

    private var chipPositionBinding: Binding<ChipPosition> {
        Binding(
            get: { appState.chipPosition },
            set: { newValue in
                appState.chipPosition = newValue
                appState.coordinator?.setChipPosition(newValue)
            }
        )
    }

    private var handsFreeBinding: Binding<HotkeyConfiguration> {
        Binding(
            get: { appState.handsFreeConfig },
            set: { newValue in
                appState.handsFreeConfig = newValue
                appState.coordinator?.switchHotkeyMode()
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginEnabled },
            set: { newValue in
                launchAtLoginEnabled = newValue
                setLaunchAtLogin(newValue)
            }
        )
    }

    // MARK: - Helpers

    private var performanceEstimate: String {
        let asr = appState.selectedASRModel
        let llm = appState.selectedLLMModel
        let asrTime = asr.contains("tiny") ? "~0.1s" : asr.contains("turbo") ? "~1.2s" : "~0.5s"
        let llmTime = llm.contains("0.6B") || llm.contains("0.3B") ? "~0.5s" :
                       llm.contains("1.7B") || llm.contains("1B") ? "~1.3s" : "~0.5s"
        return "\(asrTime) + \(llmTime)"
    }

    private func syncLaunchAtLoginState() {
        guard #available(macOS 13.0, *) else { return }
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            launchAtLoginError = "Launch at login requires macOS 13 or newer."
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginEnabled.toggle()
            launchAtLoginError = error.localizedDescription
        }
    }
}
