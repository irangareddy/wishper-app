import SwiftUI

@main
struct WishperApp: App {
    @StateObject private var appState: AppState
    @State private var coordinator: PipelineCoordinator?

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(appState: appState)
        } label: {
            if appState.isRecording {
                Image(systemName: "waveform.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
            } else {
                // TODO: Replace with custom transparent wishper icon
                // Export just the waveform arcs + dot (no background) as PDF
                Image(systemName: "waveform.and.mic")
            }
        }

        Window("Wishper", id: "main") {
            MainWindowView(appState: appState)
        }
        .defaultSize(width: 800, height: 600)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView(appState: appState)
                .navigationTitle("Settings")
        }
        .defaultSize(width: 500, height: 400)
        .windowResizability(.contentSize)
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
