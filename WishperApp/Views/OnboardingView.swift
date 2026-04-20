import AVFoundation
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var appState: AppState
    var onComplete: () -> Void

    @State private var currentStep = 0
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var inputMonitoringGranted = CGPreflightListenEventAccess()
    @State private var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    private var modelsReady: Bool { appState.modelPreparationPhase == .ready }
    private var modelsFailed: Bool { appState.modelPreparationPhase == .failed }
    private var modelProgress: Double { max(appState.modelPreparationProgress, 0.03) }

    private var permissionsComplete: Bool {
        accessibilityGranted && inputMonitoringGranted && microphoneGranted
    }

    var body: some View {
        ZStack {
            shaderBackground
            ambientHighlights

            VStack(spacing: 0) {
                // Step indicator
                if currentStep > 0 {
                    stepIndicator
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                }

                Spacer(minLength: 0)

                // Step content
                Group {
                    switch currentStep {
                    case 0: welcomeStep
                    case 1: permissionsStep
                    case 2: modelsStep
                    default: doneStep
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer(minLength: 0)
            }
            .padding(28)
            .frame(maxWidth: 460)
        }
        .animation(.smooth(duration: 0.3), value: currentStep)
        .onAppear(perform: refreshPermissions)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
            autoAdvance()
        }
        .onChange(of: appState.modelPreparationPhase) { _, _ in
            autoAdvance()
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(1...3, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? Color.white.opacity(0.6) : Color.white.opacity(0.15))
                    .frame(width: step == currentStep ? 20 : 8, height: 4)
            }
        }
        .animation(.smooth(duration: 0.3), value: currentStep)
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .padding(24)
                .adaptiveGlass(in: Circle())

            VStack(spacing: 10) {
                Text("Set Up Wishper")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Private, on-device voice-to-text.\nGrant a few permissions and you're ready to dictate.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button("Get Started") {
                currentStep = 1
            }
            .adaptiveGlassProminentButtonStyle()
            .controlSize(.large)
            .padding(.top, 8)
        }
    }

    // MARK: - Step 1: Permissions

    private var permissionsStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Permissions")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Wishper needs these to work globally on your Mac.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                permissionRow(
                    icon: "figure.wave",
                    iconTint: accessibilityGranted ? .green : .primary,
                    title: "Accessibility",
                    description: "Insert text into the active app.",
                    granted: accessibilityGranted
                ) {
                    HotkeyPermissionGuide.openAccessibilityGuide()
                }

                divider

                permissionRow(
                    icon: "keyboard",
                    iconTint: inputMonitoringGranted ? .green : .primary,
                    title: "Input Monitoring",
                    description: "Detect push-to-talk shortcuts globally.",
                    granted: inputMonitoringGranted
                ) {
                    _ = HotkeyPermissionGuide.requestInputMonitoringAccess()
                }

                divider

                permissionRow(
                    icon: "mic.fill",
                    iconTint: microphoneGranted ? .green : .primary,
                    title: "Microphone",
                    description: "Record audio locally on your Mac.",
                    granted: microphoneGranted
                ) {
                    Task {
                        microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
                        appState.microphonePermissionGranted = microphoneGranted
                    }
                }
            }
            .padding(.vertical, 6)
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            if permissionsComplete {
                Button("Continue") {
                    currentStep = 2
                }
                .adaptiveGlassProminentButtonStyle()
                .controlSize(.large)
                .padding(.top, 4)
            } else {
                Button("Continue Anyway") {
                    currentStep = 2
                }
                .adaptiveGlassButtonStyle()
                .controlSize(.large)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Step 2: Models

    private var modelsStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("Speech Models")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Downloading local ASR and VAD models for on-device transcription.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                if modelsReady {
                    Label("Models ready", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.green)
                } else if modelsFailed {
                    VStack(spacing: 8) {
                        Label("Download failed", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.red)

                        if let error = appState.modelPreparationError {
                            Text(error)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        Button("Retry") {
                            appState.coordinator?.retryPreparation()
                        }
                        .adaptiveGlassButtonStyle()
                        .controlSize(.small)
                        .tint(.red)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(appState.modelPreparationDetail)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            Spacer(minLength: 12)

                            Text("\(Int(modelProgress * 100))%")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        ProgressView(value: modelProgress, total: 1.0)
                            .progressViewStyle(.linear)
                    }
                    .padding(20)
                    .adaptiveGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }

            if modelsReady {
                Button("Continue") {
                    currentStep = 3
                }
                .adaptiveGlassProminentButtonStyle()
                .controlSize(.large)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Step 3: Done

    private var doneStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            VStack(spacing: 10) {
                Text("You're All Set")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Hold your push-to-talk key to start dictating.\nWishper lives in your menu bar.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button("Start Using Wishper", action: onComplete)
                .adaptiveGlassProminentButtonStyle()
                .controlSize(.large)
                .padding(.top, 8)
        }
    }

    // MARK: - Shared Components

    private func permissionRow(
        icon: String,
        iconTint: Color,
        title: String,
        description: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(description)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if granted {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button(title == "Accessibility" ? "Guide Me" : "Grant", action: action)
                    .adaptiveGlassButtonStyle()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Divider()
            .overlay(Color.white.opacity(0.08))
            .padding(.horizontal, 18)
    }

    // MARK: - Background

    private var shaderBackground: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .windowBackgroundColor),
                                Color(nsColor: .underPageBackgroundColor)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .colorEffect(
                        ShaderLibrary.gradientWave(
                            .float2(Float(geo.size.width), Float(geo.size.height)),
                            .float(Float(time))
                        )
                    )
                    .opacity(0.45)
            }
        }
        .ignoresSafeArea()
    }

    private var ambientHighlights: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.18))
                .blur(radius: 80)
                .frame(width: 220, height: 220)
                .offset(x: -120, y: -140)

            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .blur(radius: 110)
                .frame(width: 260, height: 260)
                .offset(x: 150, y: 160)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Logic

    private func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        microphoneGranted = mic == .authorized
        appState.microphonePermissionGranted = microphoneGranted
    }

    private func autoAdvance() {
        if currentStep == 1 && permissionsComplete {
            currentStep = 2
        }
        if currentStep == 2 && modelsReady {
            currentStep = 3
        }
    }
}

#Preview {
    OnboardingView(appState: AppState(), onComplete: {})
        .frame(width: 540, height: 480)
}
