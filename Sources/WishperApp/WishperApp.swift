import SwiftUI

@main
struct WishperApp: App {
    @StateObject private var appState = AppState()
    @State private var coordinator: PipelineCoordinator?

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: appState.isRecording ? "waveform.circle.fill" : "waveform.circle")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appState: appState)
        }
    }

    init() {
        // Start the pipeline on launch
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        let coord = PipelineCoordinator(appState: state)
        _coordinator = State(initialValue: coord)
        Task { @MainActor in
            await coord.start()
        }
    }
}
