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
            MenuBarMenu(appState: appState, onOpenWindow: {
                NSApp.setActivationPolicy(.regular)
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            })
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
        let monitor = MemoryMonitor()
        state.memoryMonitor = monitor
        _appState = StateObject(wrappedValue: state)
        let coord = PipelineCoordinator(appState: state, memoryMonitor: monitor)
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
        if !flag {
            NSApp.setActivationPolicy(.regular)
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

    func applicationDidResignActive(_ notification: Notification) {
        // Switch back to accessory when no visible windows remain
        let hasVisibleWindows = NSApp.windows.contains { window in
            window.isVisible && !window.className.contains("Panel")
        }
        if !hasVisibleWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
