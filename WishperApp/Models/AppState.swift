import Combine
import SwiftUI

/// A single transcript history entry, persistable to disk.
struct TranscriptEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let raw: String
    let cleaned: String

    init(raw: String, cleaned: String) {
        self.id = UUID()
        self.date = Date()
        self.raw = raw
        self.cleaned = cleaned
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var isCleaning = false
    @Published var lastTranscription = ""
    @Published var lastCleanedText = ""
    @Published var selectedASRModel = "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
    @Published var selectedLLMModel = "mlx-community/Qwen3-0.6B-4bit"
    @Published var cleanupEnabled = false
    @Published var transcriptionLanguage = "en"
    @Published var pushToTalkKey = "fn"
    @Published var cancelKey = "esc"
    @Published var handsFreeConfig = HotkeyConfiguration.fnSpace
    @Published var soundsEnabled = true
    @Published var chipPosition: ChipPosition = .belowNotch
    @Published var statusMessage = "Ready"
    @Published var liveTranscript = ""
    @Published var recordingStartedAt: Date?
    let stats = StatsTracker()
    var memoryMonitor: MemoryMonitor?
    weak var coordinator: PipelineCoordinator?

    // Transcript history — persisted to disk
    @Published var history: [TranscriptEntry] = []

    private static let historyFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("WishperApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("transcript_history.json")
    }()

    init() {
        loadHistory()
    }

    func addToHistory(raw: String, cleaned: String) {
        let entry = TranscriptEntry(raw: raw, cleaned: cleaned)
        history.insert(entry, at: 0)
        if history.count > 50 { history.removeLast() }
        saveHistory()
    }

    func deleteFromHistory(id: UUID) {
        history.removeAll { $0.id == id }
        saveHistory()
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: Self.historyFileURL),
              let entries = try? JSONDecoder().decode([TranscriptEntry].self, from: data)
        else { return }
        history = entries
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: Self.historyFileURL, options: .atomic)
    }
}
