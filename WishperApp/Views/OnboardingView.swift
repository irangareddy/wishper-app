import AVFoundation
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var appState: AppState
    var onComplete: () -> Void

    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var inputMonitoringGranted = CGPreflightListenEventAccess()
    @State private var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    private var modelsReady: Bool { appState.modelPreparationPhase == .ready }
    private var modelsFailed: Bool { appState.modelPreparationPhase == .failed }
    private var modelProgress: Double { max(appState.modelPreparationProgress, 0.03) }

    private var allDone: Bool {
        accessibilityGranted && inputMonitoringGranted && microphoneGranted && modelsReady
    }

    var body: some View {
        ZStack {
            shaderBackground
            ambientHighlights

            ScrollView(.vertical, showsIndicators: false) {
                GlassEffectContainer(spacing: 18) {
                    VStack(spacing: 18) {
                        heroPanel
                        checklistPanel
                        footerPanel
                    }
                    .padding(24)
                }
                .frame(maxWidth: 490)
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(
            minWidth: 520,
            idealWidth: 540,
            maxWidth: 620,
            minHeight: 520,
            idealHeight: 560,
            maxHeight: 760,
            alignment: .top
        )
        .onAppear(perform: refreshPermissions)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

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
                    .opacity(0.2)
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

    private var heroPanel: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Private on-device setup", systemImage: "lock.badge.waveform")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text("Set Up Wishper")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Grant the required permissions, let Wishper prepare local speech models, and then start dictating without leaving your Mac.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "waveform.and.mic")
                .font(.system(size: 28, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .padding(18)
                .glassEffect(.regular, in: Circle())
        }
        .padding(24)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var checklistPanel: some View {
        VStack(spacing: 0) {
            checklistRow(
                icon: "figure.wave",
                iconTint: accessibilityGranted ? .green : .primary,
                title: "Accessibility",
                description: "Needed to insert text into the app you are dictating into.",
                status: accessibilityGranted ? .done : .action("Guide Me")
            ) {
                HotkeyPermissionGuide.openAccessibilityGuide()
            }

            divider

            checklistRow(
                icon: "keyboard",
                iconTint: inputMonitoringGranted ? .green : .primary,
                title: "Input Monitoring",
                description: "Needed to detect fn and modifier-key push-to-talk shortcuts globally.",
                status: inputMonitoringGranted ? .done : .action("Enable")
            ) {
                _ = HotkeyPermissionGuide.requestInputMonitoringAccess()
            }

            divider

            checklistRow(
                icon: "mic.fill",
                iconTint: microphoneGranted ? .green : .primary,
                title: "Microphone",
                description: "Wishper records locally and never sends raw audio to a server.",
                status: microphoneGranted ? .done : .action("Grant")
            ) {
                Task {
                    microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
                    appState.microphonePermissionGranted = microphoneGranted
                }
            }

            divider

            checklistRow(
                icon: "shippingbox.fill",
                iconTint: modelIconTint,
                title: "Speech Models",
                description: "Required local ASR and VAD models for the first transcription.",
                status: modelStatus
            ) {
                appState.coordinator?.retryPreparation()
            }

            if appState.modelPreparationPhase == .preparing || appState.modelPreparationPhase == .idle {
                divider

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(appState.modelPreparationDetail)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        Spacer(minLength: 12)

                        Text("\(Int(modelProgress * 100))%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    ProgressView(value: modelProgress, total: 1.0)
                        .progressViewStyle(.linear)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            if modelsFailed, let error = appState.modelPreparationError {
                divider

                Text(error)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
        }
        .padding(.vertical, 6)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var footerPanel: some View {
        VStack(spacing: 12) {
            if allDone {
                Button("Start Using Wishper", action: onComplete)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            } else {
                Text(footerMessage)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, allDone ? 0 : 8)
    }

    private var divider: some View {
        Divider()
            .overlay(Color.white.opacity(0.08))
            .padding(.horizontal, 20)
    }

    private var footerMessage: String {
        if modelsFailed {
            return "Retry the speech model download to finish setup."
        }
        return "Complete the four items above to unlock dictation."
    }

    private var modelIconTint: Color {
        switch appState.modelPreparationPhase {
        case .ready:
            .green
        case .failed:
            .red
        case .idle, .preparing:
            .accentColor
        }
    }

    private var modelStatus: RowStatus {
        switch appState.modelPreparationPhase {
        case .ready:
            .done
        case .failed:
            .failed("Retry")
        case .idle:
            .progress(modelProgress, "Queued")
        case .preparing:
            .progress(modelProgress, "Preparing")
        }
    }

    private enum RowStatus {
        case done
        case action(String)
        case progress(Double, String)
        case failed(String)
    }

    private func checklistRow(
        icon: String,
        iconTint: Color,
        title: String,
        description: String,
        status: RowStatus,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(description)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            statusBadge(status, action: action)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func statusBadge(_ status: RowStatus, action: @escaping () -> Void) -> some View {
        switch status {
        case .done:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        case .action(let label):
            Button(label, action: action)
                .buttonStyle(.glass)
                .controlSize(.small)
        case .progress(let progress, let label):
            VStack(alignment: .trailing, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .failed(let label):
            Button(label, action: action)
                .buttonStyle(.glass)
                .controlSize(.small)
                .tint(.red)
        }
    }

    private func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        microphoneGranted = mic == .authorized
        appState.microphonePermissionGranted = microphoneGranted
    }
}

#Preview {
    OnboardingView(appState: AppState(), onComplete: {})
        .frame(width: 540, height: 520)
}
