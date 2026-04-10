import Foundation

/// Orchestrates the full voice-to-text pipeline:
/// hotkey → record → transcribe → voice commands → LLM cleanup → paste
@MainActor
final class PipelineCoordinator {
    let appState: AppState
    private let recorder = AudioRecorder()
    private let transcriber: Transcriber
    private let cleaner: Cleaner
    private let injector = TextInjector()
    private let hotkeyManager = HotkeyManager()
    private let sounds = SoundPlayer()

    private var isProcessing = false

    init(appState: AppState) {
        self.appState = appState
        self.transcriber = Transcriber(model: appState.selectedASRModel)
        self.cleaner = Cleaner(model: appState.selectedLLMModel, enabled: appState.cleanupEnabled)
    }

    func start() async {
        // Load models in background
        appState.statusMessage = "Loading ASR model..."
        do {
            try await transcriber.loadModel()
            appState.statusMessage = "Loading LLM model..."
            try await cleaner.loadModel()
            appState.statusMessage = "Ready"
        } catch {
            appState.statusMessage = "Model load failed: \(error.localizedDescription)"
            return
        }

        // Set up hotkey callbacks
        hotkeyManager.onRecordingStart = { [weak self] in
            Task { @MainActor in
                self?.startRecording()
            }
        }
        hotkeyManager.onRecordingStop = { [weak self] in
            Task { @MainActor in
                await self?.stopAndProcess()
            }
        }
        hotkeyManager.start(mode: .pushToTalk)
    }

    func stop() {
        hotkeyManager.stop()
        recorder.stop()
    }

    private func startRecording() {
        guard !recorder.isRecording, !isProcessing else { return }
        do {
            try recorder.start()
            appState.isRecording = true
            appState.statusMessage = "Recording..."
            if appState.soundsEnabled { sounds.startRecording() }
        } catch {
            appState.statusMessage = "Mic error: \(error.localizedDescription)"
            if appState.soundsEnabled { sounds.error() }
        }
    }

    private func stopAndProcess() async {
        guard recorder.isRecording else { return }
        recorder.stop()
        appState.isRecording = false
        if appState.soundsEnabled { sounds.stopRecording() }

        guard !recorder.isSilent() else {
            appState.statusMessage = "No speech detected"
            return
        }

        isProcessing = true
        let audio = recorder.getAudio()

        // Transcribe
        appState.isTranscribing = true
        appState.statusMessage = "Transcribing..."
        do {
            let raw = try await transcriber.transcribe(audioArray: audio)
            appState.lastTranscription = raw
            appState.isTranscribing = false

            // Voice commands
            let afterCommands = VoiceCommands.process(raw)

            // LLM cleanup
            var cleaned = afterCommands
            if appState.cleanupEnabled {
                appState.isCleaning = true
                appState.statusMessage = "Cleaning..."
                let app = AppContext.getActiveApp()
                let tone = AppContext.getTone(for: app)
                cleaned = try await cleaner.clean(rawText: afterCommands, appContext: tone)
                appState.isCleaning = false
            }

            appState.lastCleanedText = cleaned

            // Inject
            let success = injector.inject(cleaned)
            if success {
                appState.statusMessage = "Ready"
                appState.addToHistory(raw: raw, cleaned: cleaned)
                if appState.soundsEnabled { sounds.done() }
            } else {
                appState.statusMessage = "Paste failed"
                if appState.soundsEnabled { sounds.error() }
            }
        } catch {
            appState.statusMessage = "Error: \(error.localizedDescription)"
            appState.isTranscribing = false
            appState.isCleaning = false
            if appState.soundsEnabled { sounds.error() }
        }

        isProcessing = false
    }
}
