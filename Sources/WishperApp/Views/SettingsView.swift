import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        TabView {
            GeneralSettingsView(appState: appState)
                .tabItem { Label("General", systemImage: "gearshape") }
            
            ModelSettingsView(appState: appState)
                .tabItem { Label("Models", systemImage: "cpu") }
            
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 400)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var appState: AppState
    @AppStorage("launchAtLoginEnabled") private var launchAtLoginEnabled = false
    @State private var launchAtLoginError: String?
    
    var body: some View {
        Form {
            Section("Capture") {
                LabeledContent("Shortcut") {
                    ShortcutRecorderView(configuration: $appState.hotkeyConfig)
                }

                Toggle("Clean up transcript with LLM", isOn: $appState.cleanupEnabled)
                Toggle("Play sounds", isOn: $appState.soundsEnabled)
                Toggle("Launch at login", isOn: launchAtLoginBinding)
            }

            if let launchAtLoginError {
                Section {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear(perform: syncLaunchAtLoginState)
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
            launchAtLoginError = "Unable to update login item settings. \(error.localizedDescription)"
        }
    }
}

struct ModelSettingsView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        Form {
            Section("Speech Recognition") {
                LabeledContent("ASR model") {
                    TextField("ASR model", text: $appState.selectedASRModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280)
                }

                Text("This model handles speech-to-text transcription and is downloaded from Hugging Face on first use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Cleanup") {
                LabeledContent("LLM model") {
                    TextField("LLM model", text: $appState.selectedLLMModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280)
                }

                Text("This model polishes transcripts before paste, preserving your existing cleanup setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    Image("menubar_icon_1x")
                        .resizable()
                        .renderingMode(.original)
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Wishper")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Version 0.1.0")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("A local macOS menu bar dictation app built on MLX for fast speech recognition and optional LLM cleanup.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Links") {
                Link("Project Repository", destination: URL(string: "https://github.com/irangareddy/wishper-app")!)
                Link("MLX Swift LM", destination: URL(string: "https://github.com/ml-explore/mlx-swift-lm")!)
                Link("speech-swift", destination: URL(string: "https://github.com/soniqo/speech-swift")!)
            }

            Section {
                Text("Wishper keeps transcription local on Apple Silicon and is designed for desktop-first dictation workflows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
