import AVFoundation
import SwiftUI

// MARK: - Onboarding Checklist

struct OnboardingView: View {
    @ObservedObject var appState: AppState
    var onComplete: () -> Void

    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    private var modelsReady: Bool { appState.modelPreparationPhase == .ready }
    private var modelsFailed: Bool { appState.modelPreparationPhase == .failed }

    private var allDone: Bool {
        accessibilityGranted && microphoneGranted && modelsReady
    }

    var body: some View {
        ZStack {
            shaderBackground

            VStack(spacing: 20) {
                Spacer()

                // Icon + Title
                VStack(spacing: 10) {
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.9))

                    Text("Set Up Wishper")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Wishper needs these permissions to\ntranscribe your speech locally.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                // Checklist
                VStack(spacing: 8) {
                    checklistRow(
                        icon: "lock.shield",
                        title: "Accessibility",
                        description: "Paste text into active apps",
                        status: accessibilityGranted ? .done : .action("Guide Me")
                    ) {
                        HotkeyPermissionGuide.openAccessibilityGuide()
                    }

                    checklistRow(
                        icon: "mic",
                        title: "Microphone",
                        description: "Record audio locally on your Mac",
                        status: microphoneGranted ? .done : .action("Grant")
                    ) {
                        Task {
                            microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
                        }
                    }

                    modelRow
                }
                .padding(.horizontal, 24)

                Spacer()

                // Footer
                if allDone {
                    Button(action: onComplete) {
                        Text("Start Using Wishper")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.15), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 40)
                } else {
                    Text("All items must show ✓ to continue.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                }

                Spacer().frame(height: 20)
            }
        }
        .frame(width: 400, height: 420)
        .background(Color(white: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
        .onChange(of: appState.modelPreparationPhase) { _, _ in
            if allDone { onComplete() }
        }
    }

    // MARK: - Shader Background

    private var shaderBackground: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Rectangle()
                .fill(Color(white: 0.08))
                .colorEffect(
                    ShaderLibrary.gradientWave(
                        .float2(400, 420),
                        .float(Float(time))
                    )
                )
                .opacity(0.5)
        }
    }

    // MARK: - Checklist Row

    private enum RowStatus {
        case done
        case action(String)
        case progress(Double, String)
        case failed(String)
    }

    private func checklistRow(
        icon: String,
        title: String,
        description: String,
        status: RowStatus,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(statusColor(status))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                Text(description)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            statusBadge(status, action: action)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statusBadge(_ status: RowStatus, action: @escaping () -> Void) -> some View {
        switch status {
        case .done:
            Text("Done ✓")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.green)
        case .action(let label):
            Button(label, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        case .progress(_, let detail):
            Text(detail)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        case .failed(let label):
            Button(label, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
        }
    }

    private func statusColor(_ status: RowStatus) -> Color {
        switch status {
        case .done: .green
        case .action: .white.opacity(0.7)
        case .progress: .blue
        case .failed: .red
        }
    }

    // MARK: - Model Row

    private var modelRow: some View {
        VStack(spacing: 0) {
            checklistRow(
                icon: "shippingbox",
                title: "Speech Models",
                description: "Local ASR + VAD (~500MB)",
                status: modelStatus
            ) {
                appState.coordinator?.retryPreparation()
            }

            if case .preparing = appState.modelPreparationPhase {
                VStack(spacing: 4) {
                    ProgressView(value: appState.modelPreparationProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.blue)

                    Text("\(appState.modelPreparationDetail) — \(Int(appState.modelPreparationProgress * 100))%")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 0))
            }
        }
    }

    private var modelStatus: RowStatus {
        switch appState.modelPreparationPhase {
        case .ready: .done
        case .failed: .failed("Retry")
        case .idle, .preparing: .progress(appState.modelPreparationProgress, "Loading...")
        }
    }

    // MARK: - Refresh

    private func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        microphoneGranted = mic == .authorized
    }
}

#Preview {
    OnboardingView(appState: AppState(), onComplete: {})
}
