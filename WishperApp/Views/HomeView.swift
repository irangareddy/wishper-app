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
                    description: Text("Start dictating from the menu bar and your transcript history will appear here.")
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(appState.history) { entry in
                            TranscriptRow(entry: entry)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .padding(24)
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

struct TranscriptRow: View {
    let entry: TranscriptEntry

    @State private var showsRawText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.headline)

                    Text(showsRawText ? "Raw transcript" : "Cleaned transcript")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button("Copy \(showsRawText ? "Raw" : "Cleaned") Text") {
                        copyCurrentText()
                    }

                    Button(showsRawText ? "Show Cleaned Text" : "Show Raw Text") {
                        showsRawText.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Text(displayText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var displayText: String {
        showsRawText ? entry.raw : entry.cleaned
    }

    private func copyCurrentText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(displayText, forType: .string)
    }
}
