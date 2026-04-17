import AVFoundation
import SwiftUI

// MARK: - Onboarding Steps

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case permissions
    case microphone
    case prepare
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @State private var currentStep: OnboardingStep = .welcome
    @State private var hotkeyPermissionState = HotkeyPermissionGuide.currentState()
    @State private var microphoneGranted = false
    var onRetryPreparation: () -> Void
    var onComplete: () -> Void

    var body: some View {
        ZStack {
            // Metal shader background
            shaderBackground

            // Content
            VStack(spacing: 0) {
                Spacer()

                stepContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .id(currentStep)

                Spacer()

                // Navigation
                HStack {
                    // Step indicators
                    HStack(spacing: 8) {
                        ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                            Circle()
                                .fill(step == currentStep ? Color.white : Color.white.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                    }

                    Spacer()

                    // Action button
                    Button(action: advanceStep) {
                        Text(buttonLabel)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(buttonEnabled ? Color.white.opacity(0.2) : Color.white.opacity(0.08))
                            )
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(!buttonEnabled)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
            }
        }
        .frame(width: 480, height: 340)
        .background(Color(white: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.35), value: currentStep)
        .background(WindowActivator())
    }

    // MARK: - Shader Background

    private var shaderBackground: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Rectangle()
                .fill(Color(white: 0.08))
                .colorEffect(
                    ShaderLibrary.gradientWave(
                        .float2(480, 340),
                        .float(Float(time))
                    )
                )
                .opacity(0.7)
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .welcome:
            welcomeStep
        case .permissions:
            permissionsStep
        case .microphone:
            microphoneStep
        case .prepare:
            preparationStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.9))
                .symbolEffect(.pulse, options: .repeating)

            Text("Welcome to Wishper")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Local voice-to-text powered by MLX.\nNo cloud. No subscription. No data leaves your Mac.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding(.horizontal, 40)
    }

    private var permissionsStep: some View {
        VStack(spacing: 16) {
            Image(systemName: hotkeyPermissionState.allGranted ? "checkmark.shield.fill" : "hand.raised.fill")
                .font(.system(size: 44))
                .foregroundStyle(hotkeyPermissionState.allGranted ? .green : .white.opacity(0.9))
                .contentTransition(.symbolEffect(.replace))

            Text("Privacy Permissions")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Wishper needs two macOS permissions for global dictation.\nAccessibility lets Wishper paste into your active app.\nInput Monitoring lets fn and Right Command work as push-to-talk keys.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            VStack(spacing: 10) {
                permissionCard(
                    title: "Accessibility",
                    description: "Required so Wishper can paste text into your active app.",
                    granted: hotkeyPermissionState.accessibilityGranted,
                    actionTitle: "Guide Me"
                ) {
                    HotkeyPermissionGuide.openAccessibilityGuide()
                }

                permissionCard(
                    title: "Input Monitoring",
                    description: "Required so fn and right-side modifier keys are detected globally.",
                    granted: hotkeyPermissionState.inputMonitoringGranted,
                    actionTitle: "Open Settings"
                ) {
                    _ = HotkeyPermissionGuide.requestInputMonitoringAccess()
                }
            }
        }
        .padding(.horizontal, 40)
        .onAppear(perform: refreshPermissionState)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionState()
        }
    }

    private var microphoneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: microphoneGranted ? "mic.fill" : "mic.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(microphoneGranted ? .green : .white.opacity(0.9))
                .contentTransition(.symbolEffect(.replace))

            Text("Microphone Access")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Wishper records audio locally on your Mac.\nNothing is sent to any server.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            if !microphoneGranted {
                Button("Grant Microphone Access") {
                    Task {
                        microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
                        appState.microphonePermissionGranted = microphoneGranted
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            } else {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
        }
        .padding(.horizontal, 40)
        .onAppear {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            microphoneGranted = status == .authorized
            appState.microphonePermissionGranted = microphoneGranted
        }
    }

    private var preparationStep: some View {
        VStack(spacing: 16) {
            preparationIconView

            Text(appState.modelPreparationHeadline)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(preparationDescription)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            if appState.modelPreparationPhase == .preparing || appState.modelPreparationPhase == .idle {
                VStack(spacing: 10) {
                    ProgressView(value: max(appState.modelPreparationProgress, 0.02), total: 1.0)
                        .progressViewStyle(.linear)

                    Text(progressFootnote)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
            }

            if appState.modelPreparationPhase == .failed {
                VStack(spacing: 12) {
                    Text(appState.modelPreparationError ?? "Unknown error")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)

                    Button("Retry Download", action: onRetryPreparation)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.red.opacity(0.18), lineWidth: 1)
                )
            }

            if appState.modelPreparationPhase == .ready {
                VStack(alignment: .leading, spacing: 10) {
                    shortcutHint("Hold", key: "fn", action: "to push-to-talk")
                    shortcutHint("Press", key: "fn Space", action: "for hands-free")
                    shortcutHint("Press", key: "⌃⌘V", action: "to paste last transcript")
                }

                Text(hotkeyPermissionState.allGranted
                     ? "Global hotkeys are ready."
                     : "If fn or Right Command does not work, enable Wishper in Privacy & Security under Accessibility and Input Monitoring.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(hotkeyPermissionState.allGranted ? .green.opacity(0.9) : .white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .padding(.horizontal, 40)
        .onAppear(perform: refreshPermissionState)
    }

    private func shortcutHint(_ prefix: String, key: String, action: String) -> some View {
        HStack(spacing: 6) {
            Text(prefix)
                .foregroundStyle(.white.opacity(0.5))
            Text(key)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            Text(action)
                .foregroundStyle(.white.opacity(0.5))
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
    }

    private func permissionCard(
        title: String,
        description: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 18))
                .foregroundStyle(granted ? .green : .white.opacity(0.75))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(description)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if granted {
                Text("Enabled")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func refreshPermissionState() {
        hotkeyPermissionState = HotkeyPermissionGuide.currentState()
    }

    // MARK: - Navigation

    private var buttonLabel: String {
        switch currentStep {
        case .welcome: "Get Started"
        case .permissions: hotkeyPermissionState.allGranted ? "Continue" : "Skip for Now"
        case .microphone: microphoneGranted ? "Continue" : "Skip for Now"
        case .prepare:
            switch appState.modelPreparationPhase {
            case .ready: "Start Using Wishper"
            case .failed: "Waiting for Retry"
            case .idle, .preparing: "Preparing Models..."
            }
        }
    }

    private var buttonEnabled: Bool {
        switch currentStep {
        case .prepare:
            appState.modelPreparationPhase == .ready
        default:
            true
        }
    }

    private var preparationIcon: String {
        switch appState.modelPreparationPhase {
        case .ready:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .idle, .preparing:
            "arrow.down.circle.fill"
        }
    }

    private var preparationAccent: Color {
        switch appState.modelPreparationPhase {
        case .ready:
            .green
        case .failed:
            .red
        case .idle, .preparing:
            .white
        }
    }

    @ViewBuilder
    private var preparationIconView: some View {
        let image = Image(systemName: preparationIcon)
            .font(.system(size: 48))
            .foregroundStyle(preparationAccent)

        switch appState.modelPreparationPhase {
        case .ready:
            image.symbolEffect(.bounce, options: .nonRepeating)
        case .failed:
            image
        case .idle, .preparing:
            image.symbolEffect(.pulse, options: .repeating)
        }
    }

    private var preparationDescription: String {
        switch appState.modelPreparationPhase {
        case .ready:
            "Everything required for fast local dictation is installed on this Mac."
        case .failed:
            "Wishper needs its local speech models before first use. Retry the download to continue."
        case .idle, .preparing:
            "Wishper is downloading and loading the local speech models it needs before your first transcription."
        }
    }

    private var progressFootnote: String {
        let percent = Int(appState.modelPreparationProgress * 100)
        return "\(appState.modelPreparationDetail)\n\(percent)% complete"
    }

    private func advanceStep() {
        if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            currentStep = next
        } else {
            onComplete()
        }
    }
}

private struct WindowActivator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ActivatingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ActivatingView else { return }
        view.activateWindowIfNeeded()
    }
}

private final class ActivatingView: NSView {
    private var activatedWindowNumber: Int?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        activateWindowIfNeeded()
    }

    func activateWindowIfNeeded() {
        guard let window else { return }
        guard activatedWindowNumber != window.windowNumber || !window.isKeyWindow else { return }

        activatedWindowNumber = window.windowNumber
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        for candidate in NSApp.windows where candidate !== window && candidate.title == "Wishper" {
            candidate.orderOut(nil)
        }

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(appState: AppState(), onRetryPreparation: {}, onComplete: {})
        .frame(width: 480, height: 340)
}
