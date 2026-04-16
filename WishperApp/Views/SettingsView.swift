import KeyboardShortcuts
import ServiceManagement
import SwiftUI

// MARK: - Settings

struct SettingsDetailView: View {
    @ObservedObject var appState: AppState
    @AppStorage("launchAtLoginEnabled") private var launchAtLoginEnabled = false
    @State private var launchAtLoginError: String?
    @State private var showAdvanced = false

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

                // ── General (consumer-facing) ──

                settingsSection("Transcription") {
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
                    toggleRow("LLM text cleanup", isOn: $appState.cleanupEnabled)
                }

                settingsSection("Shortcuts") {
                    recorderRow("Push to talk", name: .pushToTalk)
                    recorderRow("Hands-free mode", name: .handsFree)
                    recorderRow("Paste last transcript", name: .pasteLastTranscript)
                    shortcutRow("Cancel recording", symbol: "⎋")
                }

                settingsSection("Appearance") {
                    pickerRow("Chip position", selection: chipPositionBinding) {
                        ForEach(ChipPosition.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    toggleRow("Sounds", isOn: $appState.soundsEnabled)
                    toggleRow("Launch at login", isOn: launchAtLoginBinding)
                    if let launchAtLoginError {
                        Text(launchAtLoginError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 24)
                    }
                }

                // ── Advanced (tap to expand) ──

                settingsSection("Advanced") {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { showAdvanced.toggle() }
                    } label: {
                        HStack {
                            Text("Show advanced settings")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showAdvanced {
                        Divider().padding(.horizontal, 24).padding(.vertical, 4)

                        // Models
                        modelRow("Speech model", selection: $appState.selectedASRModel, options: [
                            ("Qwen3-ASR 0.6B", "aufklarer/Qwen3-ASR-0.6B-MLX-4bit", "Fast · 52 languages"),
                            ("Whisper Tiny", "mlx-community/whisper-tiny", "Fastest · lower accuracy"),
                            ("Whisper Large v3 Turbo", "mlx-community/whisper-large-v3-turbo", "Best accuracy · slower"),
                        ])
                        modelRow("Cleanup model", selection: $appState.selectedLLMModel, options: [
                            ("Qwen3 0.6B", "mlx-community/Qwen3-0.6B-4bit", "Fast · good cleanup"),
                            ("Qwen3 1.7B", "mlx-community/Qwen3-1.7B-4bit", "Better quality · slower"),
                            ("Gemma 3 1B", "mlx-community/gemma-3-1b-it-qat-4bit", "Google · QAT"),
                            ("Llama 3.2 1B", "mlx-community/Llama-3.2-1B-Instruct-4bit", "Meta"),
                        ])
                        labeledRow("Est. latency") {
                            Text(performanceEstimate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Divider().padding(.horizontal, 24).padding(.vertical, 4)

                        // Memory diagnostics
                        if let m = appState.memoryMonitor {
                            labeledRow("Memory") {
                                Text("\(m.currentResidentMB) MB")
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            labeledRow("MLX active") {
                                Text("\(m.mlxActiveMemoryMB) MB")
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            labeledRow("Pressure") {
                                Text(m.pressureLevel.displayString)
                                    .foregroundStyle(m.pressureLevel == .nominal ? .green : .orange)
                            }
                            labeledRow("ASR") {
                                Circle().fill(m.asrModelLoaded ? .green : .gray).frame(width: 7, height: 7)
                                Text(m.asrModelLoaded ? "Loaded" : "—").font(.caption).foregroundStyle(.secondary)
                            }
                            labeledRow("LLM") {
                                Circle().fill(m.llmModelLoaded ? .green : .gray).frame(width: 7, height: 7)
                                Text(m.llmModelLoaded ? "Loaded" : "—").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // ── About & Acknowledgments ──

                settingsSection("About") {
                    labeledRow("Version") {
                        Text("0.4.0").foregroundStyle(.secondary)
                    }
                    labeledRow("Engine") {
                        Text("MLX on Apple Silicon").foregroundStyle(.secondary)
                    }
                    labeledRow("Privacy") {
                        Text("100% on-device").foregroundStyle(.secondary)
                    }
                }

                settingsSection("Acknowledgments", description: "Open-source libraries powering Wishper.") {
                    acknowledgmentRow("MLX Swift", by: "Apple", url: "https://github.com/ml-explore/mlx-swift")
                    acknowledgmentRow("mlx-swift-lm", by: "Apple", url: "https://github.com/ml-explore/mlx-swift-lm")
                    acknowledgmentRow("speech-swift", by: "soniqo", url: "https://github.com/soniqo/speech-swift")
                    acknowledgmentRow("swift-transformers", by: "Hugging Face", url: "https://github.com/huggingface/swift-transformers")
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
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
    }

    private func pickerRow<V: Hashable, C: View>(
        _ label: String,
        selection: Binding<V>,
        @ViewBuilder content: () -> C
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

    private func labeledRow<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        HStack {
            Text(label)
            Spacer()
            content()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
    }

    /// KeyboardShortcuts.Recorder row — proper shortcut recording
    private func recorderRow(_ label: String, name: KeyboardShortcuts.Name) -> some View {
        HStack {
            Text(label)
            Spacer()
            KeyboardShortcuts.Recorder(for: name)
                .frame(maxWidth: 160)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
    }

    /// Fixed shortcut — read-only keycap badge
    private func shortcutRow(_ label: String, symbol: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(symbol)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
    }

    /// Model picker with friendly names and descriptions
    private func modelRow(
        _ label: String,
        selection: Binding<String>,
        options: [(name: String, id: String, detail: String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .padding(.horizontal, 24)
                .padding(.top, 6)

            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                modelOptionRow(opt: opt, isSelected: selection.wrappedValue == opt.id) {
                    selection.wrappedValue = opt.id
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func modelOptionRow(opt: (name: String, id: String, detail: String), isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.gray)
                .font(.body)
            VStack(alignment: .leading, spacing: 1) {
                Text(opt.name).font(.callout)
                Text(opt.detail).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    /// Acknowledgment row with library name, author, and link
    private func acknowledgmentRow(_ name: String, by author: String, url: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.callout)
                Text(author).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Link(destination: URL(string: url)!) {
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 5)
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
            launchAtLoginError = "Requires macOS 13+"; return
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
}
