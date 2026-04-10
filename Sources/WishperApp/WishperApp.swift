import SwiftUI

@main
struct WishperApp: App {
    @StateObject private var appState: AppState
    @State private var coordinator: PipelineCoordinator?

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(appState: appState)
        } label: {
            Image(systemName: appState.isRecording ? "waveform.circle.fill" : "waveform.circle")
        }

        Settings {
            SettingsView(appState: appState)
        }
    }

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        let coord = PipelineCoordinator(appState: state)
        _coordinator = State(initialValue: coord)
        print("[wishper] WishperApp init: scheduling start()")
        Task { @MainActor in
            await coord.start()
        }
    }
}
