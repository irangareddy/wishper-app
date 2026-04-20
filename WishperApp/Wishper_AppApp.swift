import AppKit
import AVFoundation
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
    @State private var needsOnboarding = false

    /// Setup is complete only when onboarding was done AND all requirements are still met
    private var isSetupComplete: Bool {
        onboardingCompleted
            && AXIsProcessTrusted()
            && CGPreflightListenEventAccess()
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            && appState.modelPreparationPhase == .ready
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(appState: appState, onOpenWindow: {
                NSApp.setActivationPolicy(.regular)
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            })
        } label: {
            Group {
                if appState.isRecording {
                    Image(systemName: "waveform.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                } else {
                    Image(systemName: "waveform.and.mic")
                }
            }
            .onAppear {
                if needsOnboarding {
                    needsOnboarding = false
                    // Retry multiple times to ensure window opens
                    for delay in [0.5, 1.5, 3.0] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            guard !onboardingCompleted else { return }
                            NSApp.setActivationPolicy(.regular)
                            openWindow(id: "main")
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }
                }
            }
        }

        Window("Wishper", id: "main") {
            if isSetupComplete {
                MainWindowView(appState: appState)
            } else {
                OnboardingView(appState: appState) {
                    onboardingCompleted = true
                    appState.statusMessage = "Ready"
                    coordinator?.reevaluateHotkeyPermissions(promptForPermissions: false)
                }
            }
        }
        .defaultSize(width: isSetupComplete ? 660 : 500, height: isSetupComplete ? 500 : 480)
        .windowResizability(isSetupComplete ? .contentMinSize : .contentSize)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsDetailView(appState: appState)
                .frame(minWidth: 560, minHeight: 460)
        }
    }

    init() {
        // Apply saved appearance mode after NSApp is available
        let savedMode = UserDefaults.standard.string(forKey: "appearanceMode") ?? "Dark"
        if let mode = AppearanceMode(rawValue: savedMode) {
            let appearance = mode.appearance
            Task { @MainActor in
                NSApp.appearance = appearance
            }
        }

        let state = AppState()
        let monitor = MemoryMonitor()
        let onboardingWasCompleted = UserDefaults.standard.bool(forKey: "onboardingCompleted")
        state.memoryMonitor = monitor
        _appState = StateObject(wrappedValue: state)
        let coord = PipelineCoordinator(appState: state, memoryMonitor: monitor)
        _coordinator = State(initialValue: coord)
        state.coordinator = coord
        logger.debug("app init scheduling pipeline start")
        Task { @MainActor in
            await coord.start(promptForHotkeyPermissions: onboardingWasCompleted)
        }

        // Show onboarding whenever any requirement is unmet
        let accessOk = AXIsProcessTrusted()
        let inputOk = CGPreflightListenEventAccess()
        let micOk = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if !onboardingWasCompleted || !accessOk || !inputOk || !micOk {
            needsOnboarding = true
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
