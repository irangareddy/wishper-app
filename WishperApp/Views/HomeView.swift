import AppKit
import Combine
import SwiftUI

struct HomeView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            if appState.history.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Transcripts Yet",
                    systemImage: "waveform",
                    description: Text("Start dictating and your transcript history will appear here.")
                )
                Spacer()
            } else {
                List {
                    ForEach(appState.history) { entry in
                        TranscriptRow(
                            entry: entry,
                            onDelete: { appState.deleteFromHistory(id: entry.id) }
                        )
                        .listRowSeparator(.visible)
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(.top, 24)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to Wishper")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                Text("Review recent dictation history and keep track of your local transcript activity.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                StatCard(
                    value: "\(appState.stats.weeklyStreak)",
                    label: "Week Streak",
                    emoji: appState.stats.weeklyStreak >= 4 ? "⭐" : "📅"
                )
                StatCard(
                    value: "\(appState.stats.averageWPM)",
                    label: "Avg WPM",
                    emoji: appState.stats.averageWPM >= 100 ? "🏆" : "⚡"
                )
                StatCard(
                    value: formatNumber(appState.stats.totalWords),
                    label: "Total Words",
                    emoji: appState.stats.totalWords >= 10000 ? "🚀" : "📝"
                )
                StatCard(
                    value: "\(appState.stats.appsUsed.count)",
                    label: "Apps Used",
                    emoji: appState.stats.appsUsed.count >= 10 ? "🏆" : "📱"
                )
            }
        }
    }
}

struct StatCard: View {
    let value: String
    let label: String
    let emoji: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(emoji)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

func formatNumber(_ n: Int) -> String {
    if n >= 1000 { return String(format: "%.1fK", Double(n) / 1000.0) }
    return "\(n)"
}

// MARK: - Transcript Row

struct TranscriptRow: View {
    let entry: TranscriptEntry
    let onDelete: () -> Void

    @State private var showsRawText = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Timestamp column
            Text(entry.date, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 55, alignment: .trailing)
                .padding(.top, 2)

            // Transcript text
            Text(displayText)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(nil)
        }
        .contextMenu {
            Button {
                showsRawText.toggle()
            } label: {
                Label(
                    showsRawText ? "Show AI edit" : "Undo AI edit",
                    systemImage: showsRawText ? "sparkles" : "arrow.uturn.backward"
                )
            }

            Button {
                copyText()
            } label: {
                Label("Copy transcript", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete transcript", systemImage: "trash")
            }
        }
    }

    private var displayText: String {
        let text = showsRawText ? entry.raw : entry.cleaned
        return text.isEmpty ? entry.raw : text
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayText, forType: .string)
    }
}
