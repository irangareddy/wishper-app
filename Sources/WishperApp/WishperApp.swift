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
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
            } else {
                Image("menubar_icon_1x")
                    .renderingMode(.template)
            }
        }

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
