import AudioCommon
import Foundation
import MLX
import OSLog
import Qwen3ASR
import SpeechVAD

/// Real-time streaming transcriber using VAD-driven segmentation.
///
/// Audio is fed chunk-by-chunk from the mic callback. The VAD processor
/// detects speech boundaries and dispatches completed segments to the
/// ASR model for transcription. By the time the user stops recording,
/// most audio is already transcribed.
actor StreamingTranscriber {
    private let logger = WishperLog.voicePipeline
    private var asrModel: Qwen3ASRModel?
    private var vadModel: SileroVADModel?
    private let modelId: String

    // Session state (reset per recording)
    private var vadProcessor: StreamingVADProcessor?
    private var audioBuffer: [Float] = []
    private var currentSpeechStartSample: Int?
    private var finalizedSegments: [String] = []
    private var segmentCount = 0
    private var language: String = "en"

    // Callbacks (nonisolated for use from audio thread)
    nonisolated(unsafe) var onSegmentFinalized: ((_ text: String) -> Void)?
    nonisolated(unsafe) var onSpeechActivity: ((_ isSpeaking: Bool) -> Void)?

    var isModelLoaded: Bool { asrModel != nil && vadModel != nil }

    func setCallbacks(
        onSegment: ((_ text: String) -> Void)?,
        onSpeech: ((_ isSpeaking: Bool) -> Void)?
    ) {
        self.onSegmentFinalized = onSegment
        self.onSpeechActivity = onSpeech
    }

    init(model: String = "aufklarer/Qwen3-ASR-0.6B-MLX-4bit") {
        self.modelId = model
    }

    // MARK: - Model Lifecycle

    func loadModel() async throws {
        guard asrModel == nil else { return }
        logger.info("streaming transcriber loading ASR model")
        asrModel = try await Qwen3ASRModel.fromPretrained(modelId: modelId) { progress, status in
            print("[wishper] ASR model: [\(Int(progress * 100))%] \(status)")
        }

        logger.info("streaming transcriber loading VAD model")
        vadModel = try await SileroVADModel.fromPretrained(engine: .coreml) { progress, status in
            print("[wishper] VAD model: [\(Int(progress * 100))%] \(status)")
        }
        logger.info("streaming transcriber models loaded")
    }

    func unloadModel() {
        asrModel = nil
        vadModel = nil
        vadProcessor = nil
        Memory.clearCache()
    }

    // MARK: - Session Lifecycle

    func startSession(language: String = "en") {
        guard let vadModel else { return }
        self.language = language
        audioBuffer = []
        finalizedSegments = []
        currentSpeechStartSample = nil
        segmentCount = 0
        vadProcessor = StreamingVADProcessor(model: vadModel, config: .sileroDefault)
        logger.info("streaming session started language=\(language)")
    }

    /// Feed audio samples from the mic callback. Runs VAD and transcribes completed segments.
    func feedAudio(_ samples: [Float]) {
        guard let vadProcessor, let asrModel else { return }

        let bufferStart = audioBuffer.count
        audioBuffer.append(contentsOf: samples)

        let events = vadProcessor.process(samples: samples)

        for event in events {
            switch event {
            case .speechStarted(let time):
                currentSpeechStartSample = Int(time * Float(SileroVADModel.sampleRate))
                onSpeechActivity?(true)
                logger.debug("VAD speech started at \(time)s")

            case .speechEnded(let segment):
                onSpeechActivity?(false)
                guard let startSample = currentSpeechStartSample else { continue }
                let endSample = min(Int(segment.endTime * Float(SileroVADModel.sampleRate)), audioBuffer.count)
                guard startSample < endSample else {
                    currentSpeechStartSample = nil
                    continue
                }

                let segmentAudio = Array(audioBuffer[startSample..<endSample])
                let text = asrModel.transcribe(audio: segmentAudio, sampleRate: SileroVADModel.sampleRate, language: language)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !text.isEmpty {
                    finalizedSegments.append(text)
                    segmentCount += 1
                    logger.info("segment \(self.segmentCount) transcribed: \(text.prefix(50))... (\(segmentAudio.count / SileroVADModel.sampleRate)s)")
                    onSegmentFinalized?(text)
                }
                currentSpeechStartSample = nil
            }
        }
    }

    /// Finish the session: flush VAD, transcribe any remaining speech, return all text.
    func finishSession() -> String {
        guard let vadProcessor, let asrModel else {
            return finalizedSegments.joined(separator: " ")
        }

        // Flush VAD to close any open speech segment.
        // flush() handles all open states (speech, pendingSilence, pendingSpeech)
        // so no separate tail handling is needed.
        let flushEvents = vadProcessor.flush()
        for event in flushEvents {
            switch event {
            case .speechStarted(let time):
                // flush() may emit speechStarted for pendingSpeech that meets duration threshold
                currentSpeechStartSample = Int(time * Float(SileroVADModel.sampleRate))
            case .speechEnded(let segment):
                guard let startSample = currentSpeechStartSample else { continue }
                let endSample = min(Int(segment.endTime * Float(SileroVADModel.sampleRate)), audioBuffer.count)
                guard startSample < endSample else {
                    currentSpeechStartSample = nil
                    continue
                }

                let segmentAudio = Array(audioBuffer[startSample..<endSample])
                let text = asrModel.transcribe(audio: segmentAudio, sampleRate: SileroVADModel.sampleRate, language: language)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !text.isEmpty {
                    finalizedSegments.append(text)
                    segmentCount += 1
                    logger.info("final segment \(self.segmentCount) transcribed")
                }
                currentSpeechStartSample = nil
            }
        }

        let result = finalizedSegments.joined(separator: " ")
        logger.info("streaming session finished: \(self.segmentCount) segments, \(result.count) chars")

        // Clear session state
        audioBuffer = []
        currentSpeechStartSample = nil

        return result
    }

    /// Get the accumulated text so far (for live display).
    var accumulatedText: String {
        finalizedSegments.joined(separator: " ")
    }
}
