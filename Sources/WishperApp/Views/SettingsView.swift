import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        TabView {
            GeneralSettingsView(appState: appState)
                .tabItem { Label("General", systemImage: "gear") }
            
            ModelSettingsView(appState: appState)
                .tabItem { Label("Models", systemImage: "cpu") }
            
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        Form {
            Picker("Hotkey Mode", selection: $appState.hotkeyMode) {
                Text("Push to Talk").tag("push_to_talk")
                Text("Toggle").tag("toggle")
                Text("VAD Assisted").tag("vad_assisted")
            }
            Toggle("LLM Cleanup", isOn: $appState.cleanupEnabled)
            Toggle("Sound Effects", isOn: $appState.soundsEnabled)
        }
        .padding()
    }
}

struct ModelSettingsView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        Form {
            TextField("ASR Model", text: $appState.selectedASRModel)
            TextField("LLM Model", text: $appState.selectedLLMModel)
            
            Text("Models are downloaded from HuggingFace on first use.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("wishper")
                .font(.title)
                .bold()
            Text("Local voice-to-text with LLM cleanup")
                .foregroundStyle(.secondary)
            Text("Powered by MLX on Apple Silicon")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}
