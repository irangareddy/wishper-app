import KeyboardShortcuts
import ServiceManagement
import SwiftUI

// MARK: - Settings

struct SettingsDetailView: View {
    @ObservedObject var appState: AppState
    @AppStorage("launchAtLoginEnabled") private var launchAtLoginEnabled = false
    @State private var launchAtLoginError: String?
    @State private var showAdvanced = false
    @State private var hotkeyPermissionState = HotkeyPermissionGuide.currentState()

    var body: some View {
        Form {
            // ── Transcription ──
            Section {
                Picker("Language", selection: $appState.transcriptionLanguage) {
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
                Toggle("LLM text cleanup", isOn: $appState.cleanupEnabled)
            } header: {
                Text("Transcription")
            }

            // ── Shortcuts ──
            Section {
                Picker("Push to talk", selection: $appState.pushToTalkKey) {
                    Text("fn").tag("fn")
                    Text("Right Command ⌘").tag("rightCommand")
                    Text("Right Option ⌥").tag("rightOption")
                    Text("Right Control ⌃").tag("rightControl")
                    Text("Right Shift ⇧").tag("rightShift")
                }
                KeyboardShortcuts.Recorder("Hands-free mode", name: .handsFree)
                Picker("Cancel recording", selection: $appState.cancelKey) {
                    Text("Escape ⎋").tag("esc")
                    Text("fn").tag("fn")
                    Text("⌘. (Command + Period)").tag("cmdPeriod")
                }
                KeyboardShortcuts.Recorder("Paste last transcript", name: .pasteLastTranscript)
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Push to talk: hold to record, release to transcribe. Modifier-only triggers like fn or Right Command need both Accessibility and Input Monitoring to work globally on macOS.")
            }

            Section {
                LabeledContent("Accessibility") {
                    permissionStatusLabel(hotkeyPermissionState.accessibilityGranted)
                }
                LabeledContent("Input Monitoring") {
                    permissionStatusLabel(hotkeyPermissionState.inputMonitoringGranted)
                }
                Button("Guide Accessibility Setup") {
                    HotkeyPermissionGuide.openAccessibilityGuide()
                }
                Button("Open Input Monitoring Settings") {
                    _ = HotkeyPermissionGuide.requestInputMonitoringAccess()
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Use these controls if modifier-only hotkeys stop working after onboarding.")
            }

            // ── Appearance ──
            Section {
                Picker("Chip position", selection: chipPositionBinding) {
                    ForEach(ChipPosition.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                Toggle("Sounds", isOn: $appState.soundsEnabled)
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Appearance")
            }

            // ── Advanced ──
            Section(isExpanded: $showAdvanced) {
                // Models
                Picker("Speech model", selection: $appState.selectedASRModel) {
                    Text("Qwen3-ASR 0.6B — Fast · 52 languages")
                        .tag("aufklarer/Qwen3-ASR-0.6B-MLX-4bit")
                    Text("Whisper Tiny — Fastest · lower accuracy")
                        .tag("mlx-community/whisper-tiny")
                    Text("Whisper Large v3 Turbo — Best accuracy")
                        .tag("mlx-community/whisper-large-v3-turbo")
                }

                Picker("Cleanup model", selection: $appState.selectedLLMModel) {
                    Text("Qwen3 0.6B — Fast · good cleanup")
                        .tag("mlx-community/Qwen3-0.6B-4bit")
                    Text("Qwen3 1.7B — Better quality · slower")
                        .tag("mlx-community/Qwen3-1.7B-4bit")
                    Text("Gemma 3 1B — Google · QAT")
                        .tag("mlx-community/gemma-3-1b-it-qat-4bit")
                    Text("Llama 3.2 1B — Meta")
                        .tag("mlx-community/Llama-3.2-1B-Instruct-4bit")
                }

                LabeledContent("Est. latency") {
                    Text(performanceEstimate).foregroundStyle(.secondary)
                }

                // Memory diagnostics
                if let m = appState.memoryMonitor {
                    LabeledContent("Memory") {
                        Text("\(m.currentResidentMB) MB").monospacedDigit()
                    }
                    LabeledContent("MLX active") {
                        Text("\(m.mlxActiveMemoryMB) MB").monospacedDigit()
                    }
                    LabeledContent("Pressure") {
                        Text(m.pressureLevel.displayString)
                            .foregroundStyle(m.pressureLevel == .nominal ? .green : .orange)
                    }
                    LabeledContent("ASR model") {
                        HStack(spacing: 6) {
                            Circle().fill(m.asrModelLoaded ? .green : .gray).frame(width: 7, height: 7)
                            Text(m.asrModelLoaded ? "Loaded" : "—").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("LLM model") {
                        HStack(spacing: 6) {
                            Circle().fill(m.llmModelLoaded ? .green : .gray).frame(width: 7, height: 7)
                            Text(m.llmModelLoaded ? "Loaded" : "—").foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Advanced")
            }

            // ── About ──
            Section {
                LabeledContent("Version", value: "0.4.0")
                LabeledContent("Engine", value: "MLX on Apple Silicon")
                LabeledContent("Privacy", value: "100% on-device")
            } header: {
                Text("About")
            }

            // ── Acknowledgments ──
            Section {
                acknowledgmentRow("MLX Swift", by: "Apple", url: "https://github.com/ml-explore/mlx-swift")
                acknowledgmentRow("mlx-swift-lm", by: "Apple", url: "https://github.com/ml-explore/mlx-swift-lm")
                acknowledgmentRow("speech-swift", by: "soniqo", url: "https://github.com/soniqo/speech-swift")
                acknowledgmentRow("swift-transformers", by: "Hugging Face", url: "https://github.com/huggingface/swift-transformers")
                acknowledgmentRow("KeyboardShortcuts", by: "Sindre Sorhus", url: "https://github.com/sindresorhus/KeyboardShortcuts")
                acknowledgmentRow("Permiso", by: "zats", url: "https://github.com/zats/permiso")
            } header: {
                Text("Acknowledgments")
            } footer: {
                Text("Open-source libraries powering Wishper.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            syncLaunchAtLoginState()
            refreshPermissionState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionState()
        }
    }

    // MARK: - Row Builders

    private func acknowledgmentRow(_ name: String, by author: String, url: String) -> some View {
        LabeledContent {
            Link(destination: URL(string: url)!) {
                HStack(spacing: 4) {
                    Text(author).foregroundStyle(.secondary)
                    Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        } label: {
            Text(name)
        }
    }

    private func permissionStatusLabel(_ granted: Bool) -> some View {
        Text(granted ? "Enabled" : "Needs access")
            .foregroundStyle(granted ? .green : .secondary)
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
        let t1 = asr.contains("tiny") ? "~0.1s" : asr.contains("turbo") ? "~1.2s" : "~0.5s"
        let t2 = llm.contains("0.6B") || llm.contains("0.3B") ? "~0.5s" :
                  llm.contains("1.7B") || llm.contains("1B") ? "~1.3s" : "~0.5s"
        return "\(t1) + \(t2)"
    }

    private func syncLaunchAtLoginState() {
        guard #available(macOS 13.0, *) else { return }
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            launchAtLoginError = "Requires macOS 13+"
            return
        }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginEnabled.toggle()
            launchAtLoginError = error.localizedDescription
        }
    }

    private func refreshPermissionState() {
        hotkeyPermissionState = HotkeyPermissionGuide.currentState()
    }
}
