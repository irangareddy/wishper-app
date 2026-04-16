import AppKit
import SwiftUI

struct HomeView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

            Divider()

            if appState.history.isEmpty {
                emptyState
            } else {
                transcriptList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcripts")
                .font(.title)
                .fontWeight(.bold)

            HStack(spacing: 12) {
                StatCard(value: "\(appState.stats.weeklyStreak)", label: "Week Streak")
                StatCard(value: "\(appState.stats.averageWPM)", label: "Avg WPM")
                StatCard(value: formatNumber(appState.stats.totalWords), label: "Total Words")
                StatCard(value: "\(appState.stats.appsUsed.count)", label: "Apps Used")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack {
            Spacer()
            ContentUnavailableView(
                "No Transcripts Yet",
                systemImage: "waveform",
                description: Text("Start dictating and your history will appear here.")
            )
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Transcript List

    private var transcriptList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(appState.history) { entry in
                    TranscriptRow(
                        entry: entry,
                        onDelete: { appState.deleteFromHistory(id: entry.id) }
                    )

                    if entry.id != appState.history.last?.id {
                        Divider()
                            .padding(.leading, 72)
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

private func formatNumber(_ n: Int) -> String {
    if n >= 1000 { return String(format: "%.1fK", Double(n) / 1000.0) }
    return "\(n)"
}

// MARK: - Transcript Row

private struct TranscriptRow: View {
    let entry: TranscriptEntry
    let onDelete: () -> Void

    @State private var showsRawText = false
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // Timestamp — fixed width column
            Text(entry.date, format: .dateTime.hour().minute())
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)

            // Transcript content
            VStack(alignment: .leading, spacing: 4) {
                Text(displayText)
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showsRawText {
                    Text("Showing raw transcript")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
        .background(isHovering ? Color.primary.opacity(0.03) : Color.clear)
        .onHover { isHovering = $0 }
        .contextMenu { contextMenuContent }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            showsRawText.toggle()
        } label: {
            Label(
                showsRawText ? "Show AI edit" : "Undo AI edit",
                systemImage: showsRawText ? "sparkles" : "arrow.uturn.backward"
            )
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(displayText, forType: .string)
        } label: {
            Label("Copy transcript", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive, action: onDelete) {
            Label("Delete transcript", systemImage: "trash")
        }
    }

    private var displayText: String {
        let text = showsRawText ? entry.raw : entry.cleaned
        return text.isEmpty ? entry.raw : text
    }
}
