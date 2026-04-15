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

    /// Called when the user taps the idle chip to start recording.
    var onChipTapped: (() -> Void)?
    /// Called when the user taps the stop button during recording.
    var onStopTapped: (() -> Void)?
    /// Called when the user taps the close/cancel button during recording.
    var onCancelTapped: (() -> Void)?
    /// Called when the user taps Undo after cancelling.
    var onUndoCancel: (() -> Void)?

    init() {
        let content = OverlayContent(model: model, onTap: {}, onStop: {}, onCancel: {}, onUndo: {})
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
        panel.contentView = hostingView

        // Rebuild hosting view with actual callbacks wired
        let wiredContent = OverlayContent(
            model: model,
            onTap: { [weak self] in self?.onChipTapped?() },
            onStop: { [weak self] in self?.onStopTapped?() },
            onCancel: { [weak self] in self?.onCancelTapped?() },
            onUndo: { [weak self] in self?.onUndoCancel?() }
        )
        hostingView.rootView = wiredContent

        // Start in idle — always visible
        updateMouseInteraction()
        showIdle()
    }

    func showIdle() {
        withAnimation(.snappy(duration: 0.18, extraBounce: 0.02)) {
            model.state = .idle
            model.level = 0
            model.levels = Array(repeating: 0.08, count: 11)
            model.prompt = nil
        }
        updateMouseInteraction()
        refreshPanelFrame(animated: panel.isVisible)
        panel.orderFront(nil)
    }

    func show(
        state: RecordingOverlayState,
        level: CGFloat = 0,
        levels: [CGFloat]? = nil,
        prompt: RecordingOverlayPrompt? = nil
    ) {
        withAnimation(.snappy(duration: 0.18, extraBounce: 0.02)) {
            model.state = state
            model.level = level
            model.levels = normalizedLevels(from: levels, fallbackLevel: level)
            model.prompt = prompt
        }
        updateMouseInteraction()
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

    func updateRecordingLevels(_ levels: [CGFloat]) {
        guard model.state == .recording, panel.isVisible else { return }

        let normalized = normalizedLevels(from: levels, fallbackLevel: model.level)
        guard normalized != model.levels else { return }

        withAnimation(.interactiveSpring(response: 0.12, dampingFraction: 0.84, blendDuration: 0.06)) {
            model.levels = normalized
            model.level = normalized.max() ?? model.level
        }
    }

    func hide() {
        showIdle()
    }

    func showCancelled() {
        withAnimation(.snappy(duration: 0.18)) {
            model.state = .cancelled
        }
        updateMouseInteraction()
        refreshPanelFrame(animated: true)
        panel.orderFront(nil)
    }

    func setPosition(_ position: ChipPosition) {
        model.chipPosition = position
        refreshPanelFrame(animated: true)
    }


    // MARK: - Private

    private func updateMouseInteraction() {
        // Clickable in idle and recording states, pass-through during processing
        switch model.state {
        case .idle, .recording, .cancelled:
            panel.ignoresMouseEvents = false
        case .readyPrompt, .transcribing, .cleaning, .done:
            panel.ignoresMouseEvents = true
        }
    }

    private func refreshPanelFrame(animated: Bool) {
        // Defer to avoid re-entrant layout during AppKit display cycles
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hostingView.layoutSubtreeIfNeeded()

            let fittingSize = self.hostingView.fittingSize
            let width = max(44, fittingSize.width)
            let height = max(22, fittingSize.height)
            let frame = self.frameForOverlay(width: width, height: height)

            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.allowsImplicitAnimation = true
                    context.duration = 0.16
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.panel.animator().setFrame(frame, display: true)
                }
            } else {
                self.panel.setFrame(frame, display: true)
            }
        }
    }

    private func frameForOverlay(width: CGFloat, height: CGFloat) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? .zero
        let screenFrame = screen?.frame ?? .zero
        let x = visibleFrame.midX - (width / 2)

        let y: CGFloat
        switch model.chipPosition {
        case .belowNotch:
            // Top of screen, below the notch/menu bar
            y = visibleFrame.maxY - height - 68
        case .aboveDock:
            // Bottom of screen, above the Dock
            let dockHeight = screenFrame.height - visibleFrame.height - (screenFrame.height - visibleFrame.maxY)
            y = visibleFrame.minY + max(dockHeight, 12) + 12
        }

        return NSRect(x: x, y: y, width: width, height: height)
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

    @State private var hoverTarget: HoverTarget?

    private enum HoverTarget: Equatable {
        case idle, cancel, done
    }

    var body: some View {
        VStack(spacing: 7) {
            // Prompt bubble — shown for readyPrompt OR hover hints
            if let prompt = activePrompt {
                PromptBubble(prompt: prompt)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            chipView
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .animation(.snappy(duration: 0.18, extraBounce: 0.02), value: model.state)
        .animation(.snappy(duration: 0.18, extraBounce: 0.02), value: model.prompt)
        .animation(.snappy(duration: 0.15), value: hoverTarget)
    }

    private var activePrompt: RecordingOverlayPrompt? {
        // Explicit prompt (readyPrompt state)
        if let prompt = model.prompt, model.state == .readyPrompt {
            return prompt
        }
        // Hover-driven hints
        switch hoverTarget {
        case .idle:
            return RecordingOverlayPrompt(prefix: "Tap ", hotkey: "Right Command", suffix: " to dictate")
        case .cancel:
            return RecordingOverlayPrompt(prefix: "", hotkey: "Cancel", suffix: " recording")
        case .done:
            return RecordingOverlayPrompt(prefix: "", hotkey: "Done", suffix: " — transcribe & paste")
        case nil:
            return nil
        }
    }

    @ViewBuilder
    private var chipView: some View {
        switch model.state {
        case .idle:
            IdleChip(onTap: onTap, onHover: { h in hoverTarget = h ? .idle : nil })
                .transition(.scale(scale: 0.8).combined(with: .opacity))
        case .recording:
            RecordingChip(
                levels: model.levels,
                onCancel: onCancel,
                onStop: onStop,
                onCancelHover: { h in hoverTarget = h ? .cancel : nil },
                onStopHover: { h in hoverTarget = h ? .done : nil }
            )
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        case .cancelled:
            CancelledChip(onUndo: onUndo)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        default:
            SmallPill {
                indicator
            }
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch model.state {
        case .readyPrompt:
            EmptyView()
        case .transcribing, .cleaning:
            SlowActivityBars(baseHeights: [4, 5, 6, 7, 8, 9, 8, 7, 6, 5, 4])
        case .done:
            DonePulse()
        default:
            EmptyView()
        }
    }
}

// MARK: - Recording Chip (close + waveform + stop)

private struct RecordingChip: View {
    let levels: [CGFloat]
    let onCancel: () -> Void
    let onStop: () -> Void
    var onCancelHover: (Bool) -> Void = { _ in }
    var onStopHover: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { onCancelHover($0) }

            RecordingLevelBars(levels: levels)
                .padding(.horizontal, 6)

            Button(action: onStop) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(.white.opacity(0.75))
                    .frame(width: 9, height: 9)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { onStopHover($0) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(chipBackground, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
    }

    private var chipBackground: some ShapeStyle {
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

// MARK: - Cancelled Chip (transcript cancelled + undo)

private struct CancelledChip: View {
    let onUndo: () -> Void
    @State private var progress: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Transcript cancelled")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))

                Button(action: onUndo) {
                    Text("Undo")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.92, green: 0.50, blue: 0.84))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, 6)

            // Countdown progress bar
            GeometryReader { geo in
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: geo.size.width * progress, height: 2)
            }
            .frame(height: 2)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .background(chipBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
        .onAppear {
            withAnimation(.linear(duration: 3.0)) {
                progress = 0.0
            }
        }
    }

    private var chipBackground: some ShapeStyle {
        Color(white: 0.07).opacity(0.92)
    }
}

// MARK: - Idle Chip (always visible, tappable)

private struct IdleChip: View {
    let onTap: () -> Void
    var onHover: (Bool) -> Void = { _ in }
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            Capsule()
                .fill(Color.white.opacity(isHovering ? 0.45 : 0.25))
                .frame(width: 4, height: 4)
                .frame(width: 64, height: 28)
            .background(idleBackground, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(isHovering ? 0.16 : 0.06), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(isHovering ? 0.20 : 0.10), radius: isHovering ? 6 : 4, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
            onHover(hovering)
        }
    }

    private var idleBackground: some ShapeStyle {
        Color(white: 0.08).opacity(0.88)
    }
}

// MARK: - Reusable Components

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
    let levels: [CGFloat]

    var body: some View {
        let emphasis: [CGFloat] = [0.58, 0.68, 0.80, 0.92, 1.02, 1.08, 1.02, 0.92, 0.80, 0.68, 0.58]
        let resolvedLevels = normalizedLevels

        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(resolvedLevels.enumerated()), id: \.offset) { index, level in
                let profile = emphasis[index]
                let baseHeight = 2.6 + (profile * 1.5)
                let dynamicHeight = (level * 8.2) + (profile * 2.4)
                let height = baseHeight + dynamicHeight

                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.98))
                    .frame(width: 2.2, height: height)
            }
        }
        .frame(height: 13)
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
