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
        case .readyPrompt, .transcribing, .cleaning, .done:
            panel.ignoresMouseEvents = true
        }
    }

    private func positionPanel() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? .zero
        let screenFrame = screen?.frame ?? .zero
        let w = ChipLayout.windowWidth
        let h = ChipLayout.windowHeight
        let x = visibleFrame.midX - (w / 2)

        let y: CGFloat
        switch model.chipPosition {
        case .belowNotch:
            y = visibleFrame.maxY - h - 2
        case .aboveDock:
            let dockHeight = screenFrame.height - visibleFrame.height - (screenFrame.height - visibleFrame.maxY)
            y = visibleFrame.minY + max(dockHeight, 12) + 4
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
        // Chip is FIXED at top (or bottom). Suggestions slide in below (or above).
        // Using VStack with Spacer so the chip never moves.
        VStack(spacing: 0) {
            if isTopPosition {
                // CHIP pinned to top
                chipArea
                    .padding(.top, 4)

                // Suggestions slide in from top, below the chip
                suggestionsArea
                    .padding(.top, 6)

                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)

                // Suggestions slide in from bottom, above the chip
                suggestionsArea
                    .padding(.bottom, 6)

                // CHIP pinned to bottom
                chipArea
                    .padding(.bottom, 4)
            }
        }
        .frame(width: ChipLayout.windowWidth, height: ChipLayout.windowHeight)
        .animation(.easeOut(duration: 0.12), value: hoverTarget)
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
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8), value: model.state)
    }

    /// Suggestions/hints — slides in/out without moving the chip
    @ViewBuilder
    private var suggestionsArea: some View {
        Group {
            hoverHint
        }
        .transition(isTopPosition ? .move(edge: .top).combined(with: .opacity) : .move(edge: .bottom).combined(with: .opacity))
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
        case .done:
            DoneChip()
                .transition(.opacity.animation(.easeOut(duration: 0.4)))
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
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
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
        // Just the bar — the hover suggestion comes from suggestionsArea in OverlayContent
        Capsule()
            .strokeBorder(Color.white.opacity(isHovering ? 0.5 : 0.35), lineWidth: 1)
            .frame(width: 36, height: 8)
            .contentShape(Rectangle().size(width: 120, height: 24).offset(x: -42, y: -8))
            .onTapGesture { onTap() }
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
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
        .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
    }
}

// MARK: - Processing Chip

private struct ProcessingChip: View {
    var reduceMotion: Bool = false

    var body: some View {
        SlowActivityBars(baseHeights: [4, 5, 6, 7, 8, 9, 8, 7, 6, 5, 4], reduceMotion: reduceMotion)
            .frame(width: ChipLayout.chipWidth, height: ChipLayout.chipHeight)
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
        .frame(width: ChipLayout.chipWidth, height: ChipLayout.chipHeight)
        .background(ChipBackground())
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }
}

// MARK: - Cancelled Chip

private struct CancelledChip: View {
    let onUndo: () -> Void
    @State private var progress: CGFloat = 1.0

    private let prompt = RecordingOverlayPrompt(
        prefix: "Cancelled ", hotkey: "Undo", suffix: ""
    )

    var body: some View {
        VStack(spacing: 4) {
            Button(action: onUndo) {
                PromptBubble(prompt: prompt)
            }
            .buttonStyle(.plain)

            // Progress countdown bar
            GeometryReader { geo in
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: geo.size.width * progress, height: 2)
            }
            .frame(width: ChipLayout.chipWidth, height: 2)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 3.0)) {
                progress = 0.0
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

#Preview("Done Chip") {
    DoneChip()
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

        DoneChip()

        CancelledChip(onUndo: {})
    }
    .padding(40)
    .background(Color(white: 0.15))
}
