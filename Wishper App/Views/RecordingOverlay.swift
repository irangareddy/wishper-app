import AppKit
import Combine
import SwiftUI

enum RecordingOverlayState: Equatable {
    case readyPrompt
    case recording
    case transcribing
    case cleaning
    case done
}

struct RecordingOverlayPrompt: Equatable {
    let prefix: String
    let hotkey: String
    let suffix: String
}

@MainActor
final class RecordingOverlayModel: ObservableObject {
    @Published var state: RecordingOverlayState = .recording
    @Published var level: CGFloat = 0
    @Published var prompt: RecordingOverlayPrompt?
}

@MainActor
final class RecordingOverlayController {
    private let panel: NSPanel
    private let model = RecordingOverlayModel()
    private let hostingView: NSHostingView<OverlayContent>

    init() {
        let content = OverlayContent(model: model)
        hostingView = NSHostingView(rootView: content)
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = hostingView
    }

    func show(
        state: RecordingOverlayState,
        level: CGFloat = 0,
        prompt: RecordingOverlayPrompt? = nil
    ) {
        withAnimation(.snappy(duration: 0.18, extraBounce: 0.02)) {
            model.state = state
            model.level = level
            model.prompt = prompt
        }

        refreshPanelFrame(animated: panel.isVisible)
        panel.orderFront(nil)
    }

    func updateRecordingLevel(_ level: CGFloat) {
        guard model.state == .recording, panel.isVisible else { return }

        let clampedLevel = max(0, min(level, 1))
        guard abs(model.level - clampedLevel) > 0.01 else { return }

        withAnimation(.interactiveSpring(response: 0.14, dampingFraction: 0.82, blendDuration: 0.08)) {
            model.level = clampedLevel
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func refreshPanelFrame(animated: Bool) {
        hostingView.layoutSubtreeIfNeeded()

        let fittingSize = hostingView.fittingSize
        let width = max(120, fittingSize.width)
        let height = max(22, fittingSize.height)
        let frame = frameForOverlay(width: width, height: height)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.allowsImplicitAnimation = true
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func frameForOverlay(width: CGFloat, height: CGFloat) -> NSRect {
        let screen = NSApp.mainWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? .zero
        let x = visibleFrame.midX - (width / 2)
        let y = visibleFrame.maxY - height - 68
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private struct OverlayContent: View {
    @ObservedObject var model: RecordingOverlayModel

    var body: some View {
        VStack(spacing: 7) {
            if let prompt = model.prompt, model.state == .readyPrompt {
                PromptBubble(prompt: prompt)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            SmallPill {
                indicator
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .animation(.snappy(duration: 0.18, extraBounce: 0.02), value: model.state)
        .animation(.snappy(duration: 0.18, extraBounce: 0.02), value: model.prompt)
    }

    @ViewBuilder
    private var indicator: some View {
        switch model.state {
        case .readyPrompt:
            IdleDots()
        case .recording:
            RecordingLevelBars(level: model.level)
        case .transcribing, .cleaning:
            SlowActivityBars(baseHeights: [4, 5, 6, 7, 8, 9, 8, 7, 6, 5, 4])
        case .done:
            DonePulse()
        }
    }
}

private struct PromptBubble: View {
    let prompt: RecordingOverlayPrompt

    var body: some View {
        HStack(spacing: 0) {
            Text(prompt.prefix)
                .foregroundStyle(Color.white.opacity(0.96))

            Text(prompt.hotkey)
                .foregroundStyle(Color(red: 0.92, green: 0.50, blue: 0.84))

            Text(prompt.suffix)
                .foregroundStyle(Color.white.opacity(0.96))
        }
        .font(.system(size: 13, weight: .medium, design: .default))
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(bubbleBackground, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
    }

    private var bubbleBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(white: 0.10).opacity(0.94),
                Color(white: 0.05).opacity(0.92)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct SmallPill<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            content
        }
        .frame(minWidth: 74)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(pillBackground, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
    }

    private var pillBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(white: 0.08).opacity(0.94),
                Color(white: 0.05).opacity(0.92)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct IdleDots: View {
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<9, id: \.self) { _ in
                Circle()
                    .fill(Color.white.opacity(0.32))
                    .frame(width: 1.7, height: 1.7)
            }
        }
        .frame(height: 8)
    }
}

private struct RecordingLevelBars: View {
    let level: CGFloat

    var body: some View {
        let profiles: [CGFloat] = [0.26, 0.38, 0.52, 0.70, 0.88, 1.0, 0.88, 0.70, 0.52, 0.38, 0.26]
        let clampedLevel = max(0.08, min(level, 1))

        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(profiles.enumerated()), id: \.offset) { _, profile in
                let baseHeight = 2.8 + (profile * 6.4)
                let speechLift = profile * (0.6 + (clampedLevel * 1.8))
                let height = baseHeight + speechLift
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.98))
                    .frame(width: 2.2, height: height)
            }
        }
        .frame(height: 13)
        .animation(.interactiveSpring(response: 0.14, dampingFraction: 0.82, blendDuration: 0.08), value: clampedLevel)
    }
}

private struct SlowActivityBars: View {
    let baseHeights: [CGFloat]
    @State private var animate = false

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(baseHeights.enumerated()), id: \.offset) { index, baseHeight in
                let delay = Double(index) * 0.045

                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .frame(
                        width: 2.2,
                        height: (baseHeight * 0.54) + (animate ? 2.0 : 0.35)
                    )
                    .scaleEffect(y: animate ? 1.0 : 0.82, anchor: .center)
                    .animation(
                        .easeInOut(duration: 0.38).repeatForever(autoreverses: true).delay(delay),
                        value: animate
                    )
            }
        }
        .frame(height: 12)
        .onAppear {
            animate = false
            animate = true
        }
        .onDisappear {
            animate = false
        }
    }
}

private struct DonePulse: View {
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<9, id: \.self) { _ in
                Circle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 1.9, height: 1.9)
            }
        }
        .frame(height: 8)
    }
}
