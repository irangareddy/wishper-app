import SwiftUI

@main
struct WishperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState: AppState
    @State private var coordinator: PipelineCoordinator?
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(appState: appState, onOpenWindow: { openWindow(id: "main") })
        } label: {
            if appState.isRecording {
                Image(systemName: "waveform.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
            } else {
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When Dock icon is clicked and no window is visible, show the main window
        if !flag {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows {
                if window.title == "Wishper" {
                    window.makeKeyAndOrderFront(nil)
                    return false
                }
            }
        }
        return true
    }
}
