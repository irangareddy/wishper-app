import AppKit
import OSLog
import SwiftUI

@main
struct WishperApp: App {
    private let logger = WishperLog.voicePipeline
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
            SettingsDetailView(appState: appState)
                .frame(minWidth: 560, minHeight: 460)
        }
    }

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        let coord = PipelineCoordinator(appState: state)
        _coordinator = State(initialValue: coord)
        logger.debug("app init scheduling pipeline start")
        Task { @MainActor in
            await coord.start()
        }
    }
}

@MainActor
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
