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
    // Chip dimensions (the visible pill)
    static let chipWidth: CGFloat = 130
    static let chipHeight: CGFloat = 36
    static let cornerRadius: CGFloat = 18

    // Overlay window dimensions (fixed, transparent, never resizes)
    static let windowWidth: CGFloat = 280
    static let windowHeight: CGFloat = 140
}

// MARK: - Model

@MainActor
final class RecordingOverlayModel: ObservableObject {
    @Published var state: RecordingOverlayState = .idle
    @Published var level: CGFloat = 0
    @Published var levels: [CGFloat] = Array(repeating: 0.08, count: 11)
    @Published var prompt: RecordingOverlayPrompt?
    @Published var chipPosition: ChipPosition = .belowNotch
    @Published var hotkeyLabel: String = "Right Command"
}

// MARK: - Click-Through Hosting View

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
            contentRect: NSRect(x: 0, y: 0, width: ChipLayout.windowWidth, height: ChipLayout.windowHeight),
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

    func setHotkeyLabel(_ label: String) {
        model.hotkeyLabel = label
    }

    // MARK: - Private

    private func updateMouseInteraction() {
        switch model.state {
        case .idle, .recording, .cancelled:
            panel.ignoresMouseEvents = false
        case .readyPrompt, .transcribing, .cleaning:
            panel.ignoresMouseEvents = true
        }
    }

    private func positionPanel() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? .zero
        let w = ChipLayout.windowWidth
        let h = ChipLayout.windowHeight
        let x = visibleFrame.midX - (w / 2)

        let y: CGFloat
        switch model.chipPosition {
        case .belowNotch:
            y = visibleFrame.maxY - h - 2
        case .aboveDock:
            y = visibleFrame.minY + 4
        }

        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onTap: () -> Void
    var onStop: () -> Void
    var onCancel: () -> Void
    var onUndo: () -> Void

    @State private var hoverTarget: HoverTarget?
    private enum HoverTarget { case idle, cancel, stop }

    private var isTopPosition: Bool { model.chipPosition == .belowNotch }

    var body: some View {
        VStack(spacing: 0) {
            if isTopPosition {
                chipArea
                    .padding(.top, 4)

                suggestionsArea
                    .padding(.top, 6)

                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)

                suggestionsArea
                    .padding(.bottom, 6)

                chipArea
                    .padding(.bottom, 4)
            }
        }
        .frame(width: ChipLayout.windowWidth, height: ChipLayout.windowHeight)
        .animation(.smooth(duration: 0.25), value: hoverTarget)
    }

    /// The chip area — always in the same position, never moves
    @ViewBuilder
    private var chipArea: some View {
        Group {
            if model.state == .idle {
                IdleChip(onTap: onTap, hotkeyLabel: model.hotkeyLabel, growsDown: isTopPosition)
                    .onHover { h in hoverTarget = h ? .idle : nil }
            } else {
                activeChip
            }
        }
        .animation(reduceMotion ? .none : .spring(response: 0.45, dampingFraction: 0.85), value: model.state)
    }

    /// Suggestions/hints — crossfades smoothly on hover changes
    @ViewBuilder
    private var suggestionsArea: some View {
        Group {
            hoverHint
        }
        .transition(.opacity)
        .animation(.smooth(duration: 0.25), value: hoverTarget)
    }

    @ViewBuilder
    private var activeChip: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .readyPrompt:
            if let prompt = model.prompt {
                PromptBubble(prompt: prompt)
                    .allowsHitTesting(false)
            }
        case .recording:
            RecordingChip(
                levels: model.levels,
                onCancel: onCancel,
                onStop: onStop,
                reduceMotion: reduceMotion,
                onCancelHover: { h in hoverTarget = h ? .cancel : nil },
                onStopHover: { h in hoverTarget = h ? .stop : nil }
            )
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        case .transcribing, .cleaning:
            ProcessingChip(reduceMotion: reduceMotion)
                .transition(.opacity)
        case .cancelled:
            CancelledChip(onUndo: onUndo)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    private var activePrompt: RecordingOverlayPrompt? {
        switch hoverTarget {
        case .idle:   RecordingOverlayPrompt(prefix: "Hold ", hotkey: model.hotkeyLabel, suffix: " to dictate")
        case .cancel: RecordingOverlayPrompt(prefix: "", hotkey: "Cancel", suffix: " recording")
        case .stop:   RecordingOverlayPrompt(prefix: "", hotkey: "Done", suffix: " — transcribe & paste")
        case nil:     nil
        }
    }

    @ViewBuilder
    private var hoverHint: some View {
        if let prompt = activePrompt {
            PromptBubble(prompt: prompt)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Chip Background

private struct ChipBackground: View {
    var interactive = true

    var body: some View {
        Color.clear
            .glassEffect(interactive ? .regular.interactive() : .regular, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            }
    }
}

// MARK: - Idle Chip

private struct IdleChip: View {
    let onTap: () -> Void
    var hotkeyLabel: String = "Right Command"
    var growsDown: Bool = true
    @State private var isHovering = false

    var body: some View {
        ZStack {
            ChipBackground()

            Capsule(style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.42 : 0.24))
                .frame(width: isHovering ? 18 : 14, height: 3)
        }
        .frame(width: 44, height: 12)
        .contentShape(Rectangle().size(width: 120, height: 24).offset(x: -38, y: -6))
        .onTapGesture { onTap() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.25)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Recording Chip

private struct RecordingChip: View {
    let levels: [CGFloat]
    let onCancel: () -> Void
    let onStop: () -> Void
    var reduceMotion: Bool = false
    var onCancelHover: (Bool) -> Void = { _ in }
    var onStopHover: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 30, height: ChipLayout.chipHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { onCancelHover($0) }

            RecordingLevelBars(levels: levels, reduceMotion: reduceMotion)
                .frame(maxWidth: .infinity)

            Button(action: onStop) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.red)
                    .frame(width: 30, height: ChipLayout.chipHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { onStopHover($0) }
        }
        .frame(width: ChipLayout.chipWidth, height: ChipLayout.chipHeight)
        .background(ChipBackground())
    }
}

// MARK: - Processing Chip

private struct ProcessingChip: View {
    var reduceMotion: Bool = false

    var body: some View {
        SlowActivityBars(baseHeights: [4, 5, 6, 7, 8, 9, 8, 7, 6, 5, 4], reduceMotion: reduceMotion)
            .frame(width: ChipLayout.chipWidth, height: ChipLayout.chipHeight)
            .background(ChipBackground(interactive: false))
    }
}

// MARK: - Cancelled Chip

private struct CancelledChip: View {
    let onUndo: () -> Void
    @State private var progress: CGFloat = 0.0

    var body: some View {
        Button(action: onUndo) {
            HStack(spacing: 8) {
                Text("Cancelled")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12, weight: .medium, design: .default))

                Text("Undo")
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .fixedSize()
            .glassEffect(.regular, in: Capsule())
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: geo.size.width * progress, height: 2)
                }
                .frame(height: 2)
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeOut(duration: 3.0)) {
                progress = 1.0
            }
        }
    }
}

// MARK: - Shared Components

private struct RecordingLevelBars: View {
    let levels: [CGFloat]
    var reduceMotion: Bool = false

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
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.1)
                : .interactiveSpring(response: 0.12, dampingFraction: 0.84, blendDuration: 0.06),
            value: resolvedLevels
        )
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
    var reduceMotion: Bool = false
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
                        reduceMotion
                            ? .easeOut(duration: 0.1).repeatForever(autoreverses: true).delay(delay)
                            : .easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(delay),
                        value: animate
                    )
            }
        }
        .frame(height: 14)
        .onAppear { animate = false; animate = true }
        .onDisappear { animate = false }
    }
}

// MARK: - Prompt Bubble (single hint component for all suggestions)

private struct PromptBubble: View {
    let prompt: RecordingOverlayPrompt

    var body: some View {
        HStack(spacing: 0) {
            Text(prompt.prefix)
                .foregroundStyle(.primary)
            Text(prompt.hotkey)
                .foregroundStyle(.tint)
            Text(prompt.suffix)
                .foregroundStyle(.primary)
        }
        .font(.system(size: 13, weight: .medium, design: .default))
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
    }
}

// MARK: - Previews

#Preview("Idle Chip") {
    IdleChip(onTap: {})
        .padding(40)
        .background(Color(white: 0.15))
}

#Preview("Idle Chip — Hover") {
    IdleChip(onTap: {})
        .padding(40)
        .background(Color(white: 0.15))
}

#Preview("Recording Chip") {
    RecordingChip(
        levels: [0.3, 0.5, 0.7, 0.9, 1.0, 0.8, 0.6, 0.4, 0.5, 0.7, 0.3],
        onCancel: {},
        onStop: {}
    )
    .padding(40)
    .background(Color(white: 0.15))
}

#Preview("Processing Chip") {
    ProcessingChip()
        .padding(40)
        .background(Color(white: 0.15))
}

#Preview("Cancelled Chip") {
    CancelledChip(onUndo: {})
        .padding(40)
        .background(Color(white: 0.15))
}

#Preview("Prompt Bubble") {
    PromptBubble(prompt: RecordingOverlayPrompt(
        prefix: "Hold ", hotkey: "Right Command", suffix: " to dictate"
    ))
    .padding(40)
    .background(Color(white: 0.15))
}

#Preview("All States") {
    VStack(spacing: 20) {
        IdleChip(onTap: {})

        RecordingChip(
            levels: [0.3, 0.5, 0.7, 0.9, 1.0, 0.8, 0.6, 0.4, 0.5, 0.7, 0.3],
            onCancel: {},
            onStop: {}
        )

        ProcessingChip()

        CancelledChip(onUndo: {})
    }
    .padding(40)
    .background(Color(white: 0.15))
}
