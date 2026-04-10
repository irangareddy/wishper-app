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
        print("[wishper] WishperApp init: created PipelineCoordinator and scheduling start()")
        Task { @MainActor in
            print("[wishper] WishperApp init: calling PipelineCoordinator.start()")
            await coord.start()
        }
    }
}
