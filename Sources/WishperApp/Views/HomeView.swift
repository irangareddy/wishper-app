import AppKit
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
                        ForEach(Array(appState.history.enumerated()), id: \.offset) { item in
                            TranscriptRow(entry: item.element)
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to Wishper")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                Text("Review recent dictation history and keep track of your local transcript activity.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatView(value: "\(appState.history.count)", label: "Transcripts")
        }
    }
}

struct StatView: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct TranscriptRow: View {
    let entry: (date: Date, raw: String, cleaned: String)

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
