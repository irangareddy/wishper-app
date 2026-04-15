import Combine
import ServiceManagement
import SwiftUI

/// Settings as an inline detail view within the main window
struct SettingsDetailView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(24)

            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("General").tag(0)
                Text("Models").tag(1)
                Text("Memory").tag(2)
                Text("About").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)

            Divider()
                .padding(.top, 12)

            // Content
            ScrollView {
                switch selectedTab {
                case 0: GeneralSettingsView(appState: appState)
                case 1: ModelSettingsView(appState: appState)
                case 2:
                    if let monitor = appState.memoryMonitor {
                        MemoryDiagnosticsView(memoryMonitor: monitor)
                    }
                case 3: AboutView()
                default: EmptyView()
                }
            }
        }
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var appState: AppState
    @AppStorage("launchAtLoginEnabled") private var launchAtLoginEnabled = false
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section("Recording Mode") {
                Picker("Mode", selection: hotkeyModeBinding) {
                    Text("Push to Talk").tag("push_to_talk")
                    Text("Hands Free").tag("hands_free")
                }
                .pickerStyle(.radioGroup)

                if appState.hotkeyMode == "push_to_talk" {
                    LabeledContent("Shortcut") {
                        ShortcutRecorderView(configuration: $appState.hotkeyConfig)
                    }
                    Text("Hold this key to record, release to transcribe and paste.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Toggle Shortcut", selection: $appState.handsFreeConfig) {
                        Text("Fn + Space").tag(HotkeyConfiguration.fnSpace)
                        Text("Shift + Command + Space").tag(HotkeyConfiguration.shiftCommandSpace)
                    }
                    .pickerStyle(.radioGroup)
                    Text("Press once to start recording, press again to stop and transcribe.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Transcription") {
                Toggle("Clean up with LLM", isOn: $appState.cleanupEnabled)
                Text("Remove filler words, fix grammar, and adapt tone to the active app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Feedback") {
                Toggle("Play sounds", isOn: $appState.soundsEnabled)
            }

            Section("System") {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: syncLaunchAtLoginState)
    }

    private var hotkeyModeBinding: Binding<String> {
        Binding(
            get: { appState.hotkeyMode },
            set: { newValue in
                appState.hotkeyMode = newValue
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

struct ModelSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section("Speech Recognition (ASR)") {
                Picker("Model", selection: $appState.selectedASRModel) {
                    Text("Qwen3-ASR 0.6B (Fast, 52 languages)")
                        .tag("aufklarer/Qwen3-ASR-0.6B-MLX-4bit")
                    Text("Whisper Tiny (Fastest, lower accuracy)")
                        .tag("mlx-community/whisper-tiny")
                    Text("Whisper Large v3 Turbo (Best accuracy)")
                        .tag("mlx-community/whisper-large-v3-turbo")
                }
                .pickerStyle(.radioGroup)

                LabeledContent("Custom") {
                    TextField("HuggingFace model ID", text: $appState.selectedASRModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 250)
                }

                Text("Models are downloaded from HuggingFace on first use (~300-800MB).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("LLM Cleanup") {
                Picker("Model", selection: $appState.selectedLLMModel) {
                    Text("Qwen3 0.6B 4-bit (Fast, good cleanup)")
                        .tag("mlx-community/Qwen3-0.6B-4bit")
                    Text("Qwen3 1.7B 4-bit (Better quality, slower)")
                        .tag("mlx-community/Qwen3-1.7B-4bit")
                    Text("Gemma 3 1B 4-bit (Google, QAT)")
                        .tag("mlx-community/gemma-3-1b-it-qat-4bit")
                    Text("Llama 3.2 1B 4-bit (Meta)")
                        .tag("mlx-community/Llama-3.2-1B-Instruct-4bit")
                }
                .pickerStyle(.radioGroup)

                LabeledContent("Custom") {
                    TextField("HuggingFace model ID", text: $appState.selectedLLMModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 250)
                }
            }

            Section("Performance Estimate") {
                LabeledContent("ASR + LLM latency") {
                    Text(performanceEstimate)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var performanceEstimate: String {
        let asr = appState.selectedASRModel
        let llm = appState.selectedLLMModel
        let asrTime = asr.contains("tiny") ? "~0.1s" : asr.contains("turbo") ? "~1.2s" : "~0.5s"
        let llmTime = llm.contains("0.6B") || llm.contains("0.3B") ? "~0.5s" :
                       llm.contains("1.7B") || llm.contains("1B") ? "~1.3s" : "~0.5s"
        return "\(asrTime) + \(llmTime)"
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform.and.mic")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Wishper")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Version 0.1.0")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Local voice-to-text with LLM cleanup for macOS.\nPowered by MLX on Apple Silicon.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Link("GitHub Repository", destination: URL(string: "https://github.com/irangareddy/wishper-app")!)
                Link("MLX Swift LM", destination: URL(string: "https://github.com/ml-explore/mlx-swift-lm")!)
                Link("speech-swift", destination: URL(string: "https://github.com/soniqo/speech-swift")!)
            }
            .font(.callout)

            Spacer()

            Text("No cloud. No subscription. No data leaves your Mac.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
