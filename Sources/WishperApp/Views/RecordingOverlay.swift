import AppKit
import SwiftUI

enum RecordingOverlayState: String {
    case recording = "Recording"
    case transcribing = "Transcribing"
    case cleaning = "Cleaning"
    case done = "Done"

    var color: Color {
        switch self {
        case .recording:
            .red
        case .transcribing, .cleaning:
            .orange
        case .done:
            .green
        }
    }
}

@MainActor
final class RecordingOverlayController {
    private let panel: NSPanel
    private let hostingView: NSHostingView<OverlayContent>

    init() {
        let content = OverlayContent(state: .recording)
        hostingView = NSHostingView(rootView: content)
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = hostingView
    }

    func show(state: RecordingOverlayState) {
        hostingView.rootView = OverlayContent(state: state)
        hostingView.layoutSubtreeIfNeeded()

        let fittingSize = hostingView.fittingSize
        let width = max(180, fittingSize.width)
        let height = max(44, fittingSize.height)
        panel.setFrame(frameForOverlay(width: width, height: height), display: true)
        panel.orderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func frameForOverlay(width: CGFloat, height: CGFloat) -> NSRect {
        let screen = NSApp.mainWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? .zero
        let x = visibleFrame.midX - (width / 2)
        let y = visibleFrame.maxY - height - 32
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

struct OverlayContent: View {
    let state: RecordingOverlayState

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(state.color)
                .frame(width: 10, height: 10)

            Text(state.rawValue)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }
}
