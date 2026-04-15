import AppKit
import Foundation
import MLX
import OSLog

/// Orchestrates the full voice-to-text pipeline:
/// hotkey → record → transcribe → voice commands → LLM cleanup → paste
@MainActor
final class PipelineCoordinator {
    let appState: AppState
    let memoryMonitor: MemoryMonitor
    private let recorder = AudioRecorder()
    private let streamingTranscriber: StreamingTranscriber
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

    init(appState: AppState, memoryMonitor: MemoryMonitor) {
        self.appState = appState
        self.memoryMonitor = memoryMonitor
        self.streamingTranscriber = StreamingTranscriber(model: appState.selectedASRModel)
        self.cleaner = Cleaner(model: appState.selectedLLMModel, enabled: appState.cleanupEnabled)
    }

    func start() async {
        logger.info("voice pipeline startup")

        // Cap MLX buffer cache to prevent unbounded Metal memory growth
        Memory.cacheLimit = 128 * 1024 * 1024 // 128 MB

        // Check microphone permission once at startup
        let micGranted = await AudioRecorder.checkMicPermission()
        if !micGranted {
            appState.statusMessage = "Microphone access needed — check System Settings"
            logger.info("microphone access unavailable")
            // Don't return — still set up hotkeys so accessibility gets prompted too
        } else {
            logger.info("microphone access available")
        }

        // Load ASR + VAD eagerly (always needed for push-to-talk latency)
        appState.statusMessage = "Loading ASR + VAD models..."
        do {
            try await streamingTranscriber.loadModel()
            memoryMonitor.asrModelLoaded = true

            // Load LLM only if cleanup is enabled (lazy otherwise)
            if appState.cleanupEnabled {
                appState.statusMessage = "Loading LLM model..."
                try await cleaner.loadModel()
                memoryMonitor.llmModelLoaded = true
            }

            appState.statusMessage = "Ready"
        } catch {
            logger.error("pipeline preflight failed")
            appState.statusMessage = "Model load failed: \(error.localizedDescription)"
            return
        }

        // Wire memory pressure response
        memoryMonitor.shedLLM = { [weak self] in
            Task { @MainActor in
                await self?.shedLLMModel()
            }
        }
        memoryMonitor.startPolling()

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
        hotkeyManager.onHandsFreeToggle = { [weak self] shouldStart in
            Task { @MainActor in
                if shouldStart {
                    self?.startRecording()
                } else {
                    await self?.stopAndProcess()
                }
            }
        }

        // Wire chip interactions
        overlay.onChipTapped = { [weak self] in
            self?.startRecording()
        }
        overlay.onStopTapped = { [weak self] in
            Task { @MainActor in
                await self?.stopAndProcess()
            }
        }
        overlay.onCancelTapped = { [weak self] in
            self?.cancelRecording()
        }

        // Wire global paste last transcript (Ctrl+Cmd+V)
        hotkeyManager.onPasteLastTranscript = { [weak self] in
            Task { @MainActor in
                self?.pasteLastTranscript()
            }
        }

        // Set chip position and show idle
        overlay.setPosition(appState.chipPosition)
        startHotkeys()
    }

    func setChipPosition(_ position: ChipPosition) {
        overlay.setPosition(position)
    }

    private func pasteLastTranscript() {
        let text = appState.lastCleanedText.isEmpty ? appState.lastTranscription : appState.lastCleanedText
        guard !text.isEmpty else { return }
        let targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let success = injector.inject(text, targetPID: targetPID)
        logger.info("paste last transcript success=\(success)")
    }

    func switchHotkeyMode() {
        hotkeyManager.stop()
        startHotkeys()
    }

    private func startHotkeys() {
        let pttConfig = appState.hotkeyConfig
        let hfConfig = appState.handsFreeConfig

        hotkeyManager.startDualMode(
            pttKeyCode: pttConfig.keyCode,
            pttModifiers: pttConfig.modifierFlags,
            handsFreeKeyCode: hfConfig.keyCode,
            handsFreeModifiers: hfConfig.modifierFlags
        )
        logger.info("dual hotkey mode started ptt=\(pttConfig.displayString, privacy: .public) handsFree=\(hfConfig.displayString, privacy: .public)")
        showReadyPrompt(for: pttConfig)
    }

    func stop() {
        hotkeyManager.stop()
        recorder.stop()
        memoryMonitor.stopPolling()
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

        // Start streaming transcription session
        Task {
            await streamingTranscriber.startSession()

            // Wire callbacks for live text updates
            await MainActor.run {
                self.appState.liveTranscript = ""
            }
            await streamingTranscriber.setCallbacks(
                onSegment: { [weak self] text in
                    Task { @MainActor in
                        guard let self else { return }
                        self.appState.liveTranscript = await self.streamingTranscriber.accumulatedText
                    }
                },
                onSpeech: nil
            )
        }

        // Wire audio chunk feeding to streaming transcriber
        recorder.onAudioChunk = { [weak self] samples in
            guard let self else { return }
            Task {
                await self.streamingTranscriber.feedAudio(samples)
            }
        }

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
        recorder.onAudioChunk = nil // stop feeding

        // Finish streaming transcription (only processes last incomplete segment)
        appState.isTranscribing = true
        appState.statusMessage = "Finishing transcription..."
        overlay.show(state: .transcribing)
        logger.info("finishing streaming transcription")
        do {
            let raw = await streamingTranscriber.finishSession()
            appState.lastTranscription = raw
            appState.isTranscribing = false
            appState.liveTranscript = ""
            logger.info("transcription completed: \(raw.count) chars")

            // Voice commands
            let afterCommands = VoiceCommands.process(raw)

            // LLM cleanup
            var cleaned = afterCommands
            if appState.cleanupEnabled {
                // Reload LLM on demand if it was shed due to memory pressure
                if !(await cleaner.isModelLoaded) {
                    appState.statusMessage = "Loading LLM..."
                    overlay.show(state: .cleaning)
                    logger.info("reloading LLM after memory shed")
                    try await cleaner.loadModel()
                    memoryMonitor.llmModelLoaded = true
                }
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

    private func shedLLMModel() async {
        logger.warning("shedding LLM model due to memory pressure")
        await cleaner.unloadModel()
        memoryMonitor.llmModelLoaded = false
        Memory.clearCache()
    }

    private func cancelRecording() {
        recorder.stop()
        recorder.onAudioChunk = nil
        cancelOverlayMetering()
        cancelOverlayHide()
        isProcessing = false
        appState.isRecording = false
        appState.recordingStartedAt = nil
        appState.isTranscribing = false
        appState.isCleaning = false
        appState.statusMessage = "Cancelled"
        appState.liveTranscript = ""
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
                prefix: "Tap mic or hold ",
                hotkey: config.displayString,
                suffix: " to dictate"
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
                if self.recorder.bufferUsageFraction > 0.8 {
                    self.appState.statusMessage = "Recording limit approaching..."
                }
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
