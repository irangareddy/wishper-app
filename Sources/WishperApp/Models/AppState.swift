import SwiftUI
import Observation

@Observable
final class AppState: ObservableObject {
    var isRecording = false
    var isTranscribing = false
    var isCleaning = false
    var lastTranscription = ""
    var lastCleanedText = ""
    var selectedASRModel = "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
    var selectedLLMModel = "mlx-community/Qwen3-0.6B-4bit"
    var cleanupEnabled = true
    var hotkeyMode = "push_to_talk"  // push_to_talk, toggle, vad_assisted
    var hotkeyConfig = HotkeyConfiguration.rightCommand
    var soundsEnabled = true
    var statusMessage = "Ready"
    
    // Transcript history
    var history: [(date: Date, raw: String, cleaned: String)] = []
    
    func addToHistory(raw: String, cleaned: String) {
        history.insert((date: Date(), raw: raw, cleaned: cleaned), at: 0)
        if history.count > 50 { history.removeLast() }
    }
}
