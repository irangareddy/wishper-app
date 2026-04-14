import Combine
import SwiftUI

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
    @Published var hotkeyMode = "push_to_talk"
    @Published var hotkeyConfig = HotkeyConfiguration.rightCommand
    @Published var soundsEnabled = true
    @Published var statusMessage = "Ready"
    @Published var recordingStartedAt: Date?
    let stats = StatsTracker()
    var memoryMonitor: MemoryMonitor?

    // Transcript history
    @Published var history: [(date: Date, raw: String, cleaned: String)] = []

    func addToHistory(raw: String, cleaned: String) {
        history.insert((date: Date(), raw: raw, cleaned: cleaned), at: 0)
        if history.count > 50 { history.removeLast() }
    }
}
