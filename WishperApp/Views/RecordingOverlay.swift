import AppKit
import Combine
import SwiftUI

// MARK: - Types

enum RecordingOverlayState: Equatable {
    case idle
    case readyPrompt
    case recording
    case transcribing
    case cleaning
    case done
    case cancelled
}

enum ChipPosition: String, CaseIterable, Identifiable {
    case belowNotch = "Below Notch"
    case aboveDock = "Above Dock"

    var id: String { rawValue }
}

struct RecordingOverlayPrompt: Equatable {
    let prefix: String
    let hotkey: String
    let suffix: String
}

// MARK: - Constants

private enum ChipLayout {
    static let width: CGFloat = 196    // panel width (accommodates hover suggestion)
    static let height: CGFloat = 28    // chip height (compact pills)
    static let cornerRadius: CGFloat = 14
}

// MARK: - Model

@MainActor
final class RecordingOverlayModel: ObservableObject {
    @Published var state: RecordingOverlayState = .idle
    @Published var level: CGFloat = 0
    @Published var levels: [CGFloat] = Array(repeating: 0.08, count: 11)
    @Published var prompt: RecordingOverlayPrompt?
    @Published var chipPosition: ChipPosition = .belowNotch
}

// MARK: - Controller

@MainActor
final class RecordingOverlayController {
    private let panel: NSPanel
    private let model = RecordingOverlayModel()
    private let hostingView: NSHostingView<OverlayContent>

    var onChipTapped: (() -> Void)?
    var onStopTapped: (() -> Void)?
    var onCancelTapped: (() -> Void)?
    var onUndoCancel: (() -> Void)?

    init() {
        let content = OverlayContent(model: model, onTap: {}, onStop: {}, onCancel: {}, onUndo: {})
        hostingView = NSHostingView(rootView: content)

        // Fixed panel size — tall enough for bar + suggestion chip above
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: ChipLayout.width, height: ChipLayout.height + 44),
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
        panel.contentView = hostingView

        let wiredContent = OverlayContent(
            model: model,
            onTap: { [weak self] in self?.onChipTapped?() },
            onStop: { [weak self] in self?.onStopTapped?() },
            onCancel: { [weak self] in self?.onCancelTapped?() },
            onUndo: { [weak self] in self?.onUndoCancel?() }
        )
        hostingView.rootView = wiredContent

        updateMouseInteraction()
        positionPanel()
        showIdle()
    }

    func showIdle() {
        model.state = .idle
        model.level = 0
        model.levels = Array(repeating: 0.08, count: 11)
        model.prompt = nil
        updateMouseInteraction()
        panel.orderFront(nil)
    }

    func show(
        state: RecordingOverlayState,
        level: CGFloat = 0,
        levels: [CGFloat]? = nil,
        prompt: RecordingOverlayPrompt? = nil
    ) {
        model.state = state
        model.level = level
        model.levels = normalizedLevels(from: levels, fallbackLevel: level)
        model.prompt = prompt
        updateMouseInteraction()
        panel.orderFront(nil)
    }

    func updateRecordingLevel(_ level: CGFloat) {
        guard model.state == .recording, panel.isVisible else { return }
        let clampedLevel = max(0, min(level, 1))
        guard abs(model.level - clampedLevel) > 0.01 else { return }
        model.level = clampedLevel
    }

    func updateRecordingLevels(_ levels: [CGFloat]) {
        guard model.state == .recording, panel.isVisible else { return }
        let normalized = normalizedLevels(from: levels, fallbackLevel: model.level)
        guard normalized != model.levels else { return }
        model.levels = normalized
        model.level = normalized.max() ?? model.level
    }

    func hide() {
        showIdle()
    }

    func showCancelled() {
        model.state = .cancelled
        updateMouseInteraction()
        panel.orderFront(nil)
    }

    func setPosition(_ position: ChipPosition) {
        model.chipPosition = position
        positionPanel()
    }

    // MARK: - Private

    private func updateMouseInteraction() {
        switch model.state {
        case .idle, .recording, .cancelled:
            panel.ignoresMouseEvents = false
        case .readyPrompt, .transcribing, .cleaning, .done:
            panel.ignoresMouseEvents = true
        }
    }

    private static let panelHeight: CGFloat = ChipLayout.height + 44

    private func positionPanel() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? .zero
        let screenFrame = screen?.frame ?? .zero
        let x = visibleFrame.midX - (ChipLayout.width / 2)

        let y: CGFloat
        switch model.chipPosition {
        case .belowNotch:
            y = visibleFrame.maxY - Self.panelHeight - 48
        case .aboveDock:
            let dockHeight = screenFrame.height - visibleFrame.height - (screenFrame.height - visibleFrame.maxY)
            y = visibleFrame.minY + max(dockHeight, 12) + 8
        }

        panel.setFrame(NSRect(x: x, y: y, width: ChipLayout.width, height: Self.panelHeight), display: true)
    }

    private func normalizedLevels(from levels: [CGFloat]?, fallbackLevel: CGFloat) -> [CGFloat] {
        let defaultLevels = Array(repeating: max(0.08, min(fallbackLevel, 1)), count: 11)
        guard let levels, !levels.isEmpty else { return defaultLevels }
        if levels.count >= 11 {
            return Array(levels.suffix(11)).map { max(0.08, min($0, 1)) }
        }
        let paddedLevels = Array(repeating: max(0.08, min(fallbackLevel, 1)), count: 11 - levels.count) + levels
        return paddedLevels.map { max(0.08, min($0, 1)) }
    }
}

// MARK: - Overlay Content

private struct OverlayContent: View {
    @ObservedObject var model: RecordingOverlayModel
    var onTap: () -> Void
    var onStop: () -> Void
    var onCancel: () -> Void
    var onUndo: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            // Active chip states appear ABOVE the idle bar
            switch model.state {
            case .idle:
                EmptyView()
            case .readyPrompt:
                ReadyPromptChip(prompt: model.prompt)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .recording:
                RecordingChip(levels: model.levels, onCancel: onCancel, onStop: onStop)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .transcribing, .cleaning:
                ProcessingChip()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .done:
                DoneChip()
                    .transition(.opacity)
            case .cancelled:
                CancelledChip(onUndo: onUndo)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Idle bar — always at the bottom
            IdleChip(onTap: onTap, isActive: model.state != .idle)
        }
        .frame(width: ChipLayout.width)
        .animation(.snappy(duration: 0.2), value: model.state)
    }
}

// MARK: - Chip Background

private struct ChipBackground: View {
    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color(white: 0.10).opacity(0.94),
                        Color(white: 0.05).opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }
    }
}

// MARK: - Idle Chip

private struct IdleChip: View {
    let onTap: () -> Void
    var isActive: Bool = false
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            // Hover suggestion appears ABOVE the bar on Y axis
            if isHovering && !isActive {
                Button(action: onTap) {
                    HStack(spacing: 6) {
                        Text("Start recording")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))

                        Text("Fn")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .frame(width: ChipLayout.width, height: ChipLayout.height)
                    .background(ChipBackground())
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Thin bar — always visible at the bottom
            Capsule()
                .fill(Color.white.opacity(isActive ? 0.15 : (isHovering ? 0.45 : 0.3)))
                .frame(width: 50, height: 4)
                .contentShape(Rectangle().size(width: ChipLayout.width, height: 20).offset(x: -73, y: -8))
                .onTapGesture { onTap() }
        }
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Ready Prompt Chip

private struct ReadyPromptChip: View {
    let prompt: RecordingOverlayPrompt?

    var body: some View {
        Group {
            if let prompt {
                HStack(spacing: 0) {
                    Text(prompt.prefix)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(prompt.hotkey)
                        .foregroundStyle(Color(red: 0.92, green: 0.50, blue: 0.84))
                    Text(prompt.suffix)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            }
        }
        .frame(width: ChipLayout.width, height: ChipLayout.height)
        .background(ChipBackground())
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }
}

// MARK: - Recording Chip

private struct RecordingChip: View {
    let levels: [CGFloat]
    let onCancel: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 36, height: ChipLayout.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            RecordingLevelBars(levels: levels)
                .frame(maxWidth: .infinity)

            Button(action: onStop) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(.white.opacity(0.8))
                    .frame(width: 10, height: 10)
                    .frame(width: 36, height: ChipLayout.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: ChipLayout.width, height: ChipLayout.height)
        .background(ChipBackground())
        .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
    }
}

// MARK: - Processing Chip

private struct ProcessingChip: View {
    var body: some View {
        SlowActivityBars(baseHeights: [4, 5, 6, 7, 8, 9, 8, 7, 6, 5, 4])
            .frame(width: ChipLayout.width, height: ChipLayout.height)
            .background(ChipBackground())
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }
}

// MARK: - Done Chip

private struct DoneChip: View {
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<9, id: \.self) { _ in
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 2, height: 2)
            }
        }
        .frame(width: ChipLayout.width, height: ChipLayout.height)
        .background(ChipBackground())
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }
}

// MARK: - Cancelled Chip

private struct CancelledChip: View {
    let onUndo: () -> Void
    @State private var progress: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Transcript cancelled")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))

                Button(action: onUndo) {
                    Text("Undo")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.92, green: 0.50, blue: 0.84))
                }
                .buttonStyle(.plain)
            }
            .frame(height: ChipLayout.height - 4)

            GeometryReader { geo in
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: geo.size.width * progress, height: 2)
            }
            .frame(height: 2)
            .padding(.horizontal, 16)
            .padding(.bottom, 2)
        }
        .frame(width: ChipLayout.width, height: ChipLayout.height)
        .background(ChipBackground())
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        .onAppear {
            withAnimation(.linear(duration: 3.0)) {
                progress = 0.0
            }
        }
    }
}

// MARK: - Shared Components

private struct RecordingLevelBars: View {
    let levels: [CGFloat]

    var body: some View {
        let emphasis: [CGFloat] = [0.58, 0.68, 0.80, 0.92, 1.02, 1.08, 1.02, 0.92, 0.80, 0.68, 0.58]
        let resolvedLevels = normalizedLevels

        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(resolvedLevels.enumerated()), id: \.offset) { index, level in
                let profile = emphasis[index]
                let baseHeight = 2.6 + (profile * 1.5)
                let dynamicHeight = (level * 10) + (profile * 2.4)
                let height = baseHeight + dynamicHeight

                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 2.5, height: height)
            }
        }
        .frame(height: 16)
        .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.84, blendDuration: 0.06), value: resolvedLevels)
    }

    private var normalizedLevels: [CGFloat] {
        if levels.count >= 11 {
            return Array(levels.suffix(11)).map { max(0.08, min($0, 1)) }
        }
        let padding = Array(repeating: CGFloat(0.08), count: 11 - levels.count)
        return (padding + levels).map { max(0.08, min($0, 1)) }
    }
}

private struct SlowActivityBars: View {
    let baseHeights: [CGFloat]
    @State private var animate = false

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(baseHeights.enumerated()), id: \.offset) { index, baseHeight in
                let delay = Double(index) * 0.045

                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.85))
                    .frame(
                        width: 2.5,
                        height: (baseHeight * 0.54) + (animate ? 2.5 : 0.5)
                    )
                    .scaleEffect(y: animate ? 1.0 : 0.82, anchor: .center)
                    .animation(
                        .easeInOut(duration: 0.38).repeatForever(autoreverses: true).delay(delay),
                        value: animate
                    )
            }
        }
        .frame(height: 14)
        .onAppear { animate = false; animate = true }
        .onDisappear { animate = false }
    }
}

// MARK: - Legacy PromptBubble (kept for readyPrompt state)

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
        .background(
            LinearGradient(
                colors: [Color(white: 0.10).opacity(0.94), Color(white: 0.05).opacity(0.92)],
                startPoint: .top, endPoint: .bottom
            ),
            in: Capsule()
        )
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1) }
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
    }
}
