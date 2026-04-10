import AppKit
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
    private var targetApp: NSRunningApplication?

    init(appState: AppState) {
        self.appState = appState
        self.transcriber = Transcriber(model: appState.selectedASRModel)
        self.cleaner = Cleaner(model: appState.selectedLLMModel, enabled: appState.cleanupEnabled)
    }

    func start() async {
        print("[wishper] PipelineCoordinator.start() called")

        // Check microphone permission once at startup
        let micGranted = await AudioRecorder.checkMicPermission()
        if !micGranted {
            appState.statusMessage = "Microphone access denied"
            return
        }

        // Load models
        appState.statusMessage = "Loading ASR model..."
        do {
            try await transcriber.loadModel()
            print("[wishper] ASR model loaded successfully")
            appState.statusMessage = "Loading LLM model..."
            try await cleaner.loadModel()
            print("[wishper] LLM model loaded successfully")
            appState.statusMessage = "Ready"
        } catch {
            print("[wishper] Model load error: \(error)")
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
        print("[wishper] PipelineCoordinator.start(): starting HotkeyManager in \(modeDescription(.pushToTalk)) mode")
        hotkeyManager.start(mode: .pushToTalk)
    }

    func stop() {
        hotkeyManager.stop()
        recorder.stop()
    }

    private func startRecording() {
        guard !recorder.isRecording, !isProcessing else { return }
        // Save the frontmost app BEFORE we do anything
        targetApp = NSWorkspace.shared.frontmostApplication
        print("[wishper] Target app: \(targetApp?.localizedName ?? "unknown") (pid: \(targetApp?.processIdentifier ?? 0))")
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
        print("[wishper] stopAndProcess() called, isRecording=\(recorder.isRecording)")
        guard recorder.isRecording else {
            print("[wishper] stopAndProcess() skipped — not recording")
            return
        }
        recorder.stop()
        appState.isRecording = false
        if appState.soundsEnabled { sounds.stopRecording() }

        let silent = recorder.isSilent()
        print("[wishper] isSilent=\(silent), audioSamples=\(recorder.getAudio().count)")
        guard !silent else {
            appState.statusMessage = "No speech detected"
            return
        }

        isProcessing = true
        let audio = recorder.getAudio()
        print("[wishper] Audio ready: \(audio.count) samples (\(Double(audio.count)/16000.0)s)")

        // Transcribe
        appState.isTranscribing = true
        appState.statusMessage = "Transcribing..."
        print("[wishper] Starting transcription...")
        do {
            print("[wishper] Calling transcriber.transcribe()...")
            let raw = try await transcriber.transcribe(audioArray: audio)
            print("[wishper] Transcription result: \"\(raw)\"")
            appState.lastTranscription = raw
            appState.isTranscribing = false

            // Voice commands
            let afterCommands = VoiceCommands.process(raw)
            print("[wishper] After voice commands: \"\(afterCommands)\"")

            // LLM cleanup
            var cleaned = afterCommands
            if appState.cleanupEnabled {
                appState.isCleaning = true
                appState.statusMessage = "Cleaning..."
                let app = AppContext.getActiveApp()
                let tone = AppContext.getTone(for: app)
                print("[wishper] Cleaning with tone: \(tone) (app: \(app))")
                cleaned = try await cleaner.clean(rawText: afterCommands, appContext: tone)
                print("[wishper] Cleaned result: \"\(cleaned)\"")
                appState.isCleaning = false
            }

            appState.lastCleanedText = cleaned

            // Re-activate target app and inject
            if let target = targetApp {
                print("[wishper] Re-activating \(target.localizedName ?? "unknown")...")
                target.activate()
                usleep(100_000) // 100ms for app to become frontmost
            }
            print("[wishper] Injecting text...")
            let success = injector.inject(cleaned)
            print("[wishper] Injection result: \(success)")
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

    private func modeDescription(_ mode: HotkeyManager.HotkeyMode) -> String {
        switch mode {
        case .pushToTalk:
            "pushToTalk"
        case .toggle:
            "toggle"
        }
    }
}
