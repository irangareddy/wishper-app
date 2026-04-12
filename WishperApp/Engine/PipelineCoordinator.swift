import AppKit
import Foundation
import OSLog

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
    private let overlay = RecordingOverlayController()

    private var isProcessing = false
    private var targetApp: NSRunningApplication?
    private var overlayHideTask: Task<Void, Never>?
    private var overlayLevelTask: Task<Void, Never>?
    private let logger = WishperLog.voicePipeline

    init(appState: AppState) {
        self.appState = appState
        self.transcriber = Transcriber(model: appState.selectedASRModel)
        self.cleaner = Cleaner(model: appState.selectedLLMModel, enabled: appState.cleanupEnabled)
    }

    func start() async {
        logger.info("voice pipeline startup")

        // Check microphone permission once at startup
        let micGranted = await AudioRecorder.checkMicPermission()
        if !micGranted {
            appState.statusMessage = "Microphone access needed — check System Settings"
            logger.info("microphone access unavailable")
            // Don't return — still set up hotkeys so accessibility gets prompted too
        } else {
            logger.info("microphone access available")
        }

        // Load models
        appState.statusMessage = "Loading ASR model..."
        do {
            try await transcriber.loadModel()
            appState.statusMessage = "Loading LLM model..."
            try await cleaner.loadModel()
            appState.statusMessage = "Ready"
        } catch {
            logger.error("pipeline preflight failed")
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
        hotkeyManager.onCancel = { [weak self] in
            Task { @MainActor in
                self?.cancelRecording()
            }
        }
        let config = appState.hotkeyConfig
        hotkeyManager.start(
            mode: .pushToTalk,
            keyCode: config.keyCode,
            modifiers: config.modifierFlags
        )
        logger.info("voice pipeline ready hotkey=\(config.displayString, privacy: .public)")
        showReadyPrompt(for: config)
    }

    func stop() {
        hotkeyManager.stop()
        recorder.stop()
        appState.isRecording = false
        appState.recordingStartedAt = nil
        cancelOverlayMetering()
        cancelOverlayHide()
        overlay.hide()
    }

    private func startRecording() {
        guard !recorder.isRecording, !isProcessing else { return }
        cancelOverlayHide()
        cancelOverlayMetering()
        // Save the frontmost app BEFORE we do anything
        targetApp = NSWorkspace.shared.frontmostApplication
        do {
            try recorder.start()
            appState.isRecording = true
            appState.recordingStartedAt = Date()
            appState.statusMessage = "Recording..."
            overlay.show(
                state: .recording,
                level: recorder.currentNormalizedLevel(),
                levels: recorder.currentWaveformLevels()
            )
            startOverlayMetering()
            logger.info("recording started targetApp=\(self.targetAppName, privacy: .public)")
            if appState.soundsEnabled { sounds.startRecording() }
        } catch {
            logger.error("recording failed to start")
            appState.statusMessage = "Mic error: \(error.localizedDescription)"
            overlay.hide()
            if appState.soundsEnabled { sounds.error() }
        }
    }

    private func stopAndProcess() async {
        guard recorder.isRecording else {
            logger.debug("recording stop ignored because recorder was idle")
            return
        }
        recorder.stop()
        cancelOverlayMetering()
        appState.isRecording = false
        appState.recordingStartedAt = nil
        logger.info("recording stopped")
        if appState.soundsEnabled { sounds.stopRecording() }

        let silent = recorder.isSilent()
        guard !silent else {
            logger.info("silence fallback triggered")
            appState.statusMessage = "No speech detected"
            overlay.hide()
            return
        }

        isProcessing = true
        let audio = recorder.getAudio()

        // Transcribe
        appState.isTranscribing = true
        appState.statusMessage = "Transcribing..."
        overlay.show(state: .transcribing)
        logger.info("transcription started")
        do {
            let raw = try await transcriber.transcribe(audioArray: audio)
            appState.lastTranscription = raw
            appState.isTranscribing = false
            logger.info("transcription completed")

            // Voice commands
            let afterCommands = VoiceCommands.process(raw)

            // LLM cleanup
            var cleaned = afterCommands
            if appState.cleanupEnabled {
                appState.isCleaning = true
                appState.statusMessage = "Cleaning..."
                overlay.show(state: .cleaning)
                logger.info("cleanup started")
                let app = AppContext.getActiveApp()
                let tone = AppContext.getTone(for: app)
                cleaned = try await cleaner.clean(rawText: afterCommands, appContext: tone)
                appState.isCleaning = false
                logger.info("cleanup completed")
            } else {
                logger.info("cleanup skipped")
            }

            appState.lastCleanedText = cleaned

            // Inject directly to target app's PID (bypasses focus-stealing)
            let targetPID = targetApp?.processIdentifier
            logger.info("injection started targetApp=\(self.targetAppName, privacy: .public)")
            let success = injector.inject(cleaned, targetPID: targetPID)
            if success {
                appState.statusMessage = "Ready"
                appState.addToHistory(raw: raw, cleaned: cleaned)
                let duration = Double(audio.count) / 16000.0
                let appName = targetApp?.localizedName ?? "Unknown"
                appState.stats.recordTranscription(text: cleaned, durationSeconds: duration, appName: appName)
                overlay.show(state: .done)
                scheduleOverlayHide(after: 0.9)
                logger.info("injection succeeded")
                if appState.soundsEnabled { sounds.done() }
            } else {
                appState.statusMessage = "Paste failed"
                overlay.hide()
                logger.error("injection failed")
                if appState.soundsEnabled { sounds.error() }
            }
        } catch {
            logger.error("voice pipeline failed")
            logger.debug("voice pipeline error detail: \(error.localizedDescription, privacy: .public)")
            appState.statusMessage = "Error: \(error.localizedDescription)"
            appState.isTranscribing = false
            appState.isCleaning = false
            overlay.hide()
            if appState.soundsEnabled { sounds.error() }
        }

        isProcessing = false
    }

    private func cancelRecording() {
        recorder.stop()
        cancelOverlayMetering()
        cancelOverlayHide()
        isProcessing = false
        appState.isRecording = false
        appState.recordingStartedAt = nil
        appState.isTranscribing = false
        appState.isCleaning = false
        appState.statusMessage = "Cancelled"
        overlay.hide()
        logger.info("recording cancelled")
        if appState.soundsEnabled { sounds.error() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.appState.statusMessage = "Ready"
        }
    }

    private func showReadyPrompt(for config: HotkeyConfiguration) {
        overlay.show(
            state: .readyPrompt,
            prompt: RecordingOverlayPrompt(
                prefix: "Click or hold ",
                hotkey: config.displayString,
                suffix: " to start dictating"
            )
        )
        scheduleOverlayHide(after: 4)
    }

    private func scheduleOverlayHide(after seconds: Double) {
        cancelOverlayHide()
        overlayHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !self.recorder.isRecording else { return }
            self.overlay.hide()
            self.overlayHideTask = nil
        }
    }

    private func cancelOverlayHide() {
        overlayHideTask?.cancel()
        overlayHideTask = nil
    }

    private func startOverlayMetering() {
        cancelOverlayMetering()
        overlayLevelTask = Task { @MainActor [weak self] in
            while let self, self.recorder.isRecording {
                self.overlay.updateRecordingLevels(self.recorder.currentWaveformLevels())
                try? await Task.sleep(for: .milliseconds(48))
            }
            self?.overlayLevelTask = nil
        }
    }

    private func cancelOverlayMetering() {
        overlayLevelTask?.cancel()
        overlayLevelTask = nil
    }

    private var targetAppName: String {
        targetApp?.localizedName ?? "Unknown"
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
