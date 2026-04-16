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
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false

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
        .defaultSize(width: 660, height: 500)
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        // Onboarding window
        Window("Welcome to Wishper", id: "onboarding") {
            OnboardingView {
                onboardingCompleted = true
                // Close onboarding window
                NSApp.windows.first { $0.title == "Welcome to Wishper" }?.close()
                NSApp.setActivationPolicy(.accessory)
            }
            .frame(width: 480, height: 340)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)

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
        state.coordinator = coord
        logger.debug("app init scheduling pipeline start")
        Task { @MainActor in
            await coord.start()

            // Show onboarding on first launch
            if !UserDefaults.standard.bool(forKey: "onboardingCompleted") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    // Open the onboarding window
                    for window in NSApp.windows {
                        if window.title == "Welcome to Wishper" {
                            window.makeKeyAndOrderFront(nil)
                            window.center()
                            return
                        }
                    }
                }
            }
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
        let hasVisibleWindows = NSApp.windows.contains { window in
            window.isVisible && !window.className.contains("Panel")
        }
        if !hasVisibleWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
