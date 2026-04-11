import AppKit
import AVFoundation
import Foundation
import OSLog

@MainActor
final class AudioRecorder {
    private let logger = WishperLog.voicePipeline
    private var engine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private var smoothedLevel: Float = 0
    private let lock = NSLock()
    private(set) var isRecording = false
    let sampleRate: Double = 16000

    /// Check and request microphone permission once at startup
    static func checkMicPermission() async -> Bool {
        let logger = WishperLog.voicePipeline
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        logger.debug("microphone authorization status=\(status.rawValue)")

        switch status {
        case .authorized:
            logger.debug("microphone permission already granted")
            return true
        case .notDetermined:
            logger.info("microphone permission requesting")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            logger.info("microphone permission \(granted ? "granted" : "denied", privacy: .public)")
            return granted
        case .denied, .restricted:
            // Try requesting anyway — sometimes status is wrong for new bundle IDs
            logger.info("microphone permission denied attempting retry")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if granted {
                logger.info("microphone permission granted after retry")
                return true
            }
            logger.info("microphone permission denied opening system settings")
            // Open the settings pane so user can grant manually
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
            return false
        @unknown default:
            return false
        }
    }

    func start() throws {
        guard !isRecording else { return }
        audioBuffer = []
        smoothedLevel = 0

        let inputNode = engine.inputNode
        // Use the hardware's native format — don't force 16kHz
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        logger.debug("mic hardware format sampleRate=\(hardwareFormat.sampleRate, format: .fixed(precision: 0)) channels=\(hardwareFormat.channelCount)")

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        // Create a converter from hardware format to 16kHz mono
        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            throw AudioRecorderError.converterCreationFailed
        }

        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: hardwareFormat
        ) { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            guard let self else { return }

            // Calculate output frame count based on sample rate ratio
            let ratio = self.sampleRate / hardwareFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard outputFrameCount > 0 else { return }

            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outputFrameCount
            ) else { return }

            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if let error {
                self.logger.error("audio conversion error: \(error.localizedDescription, privacy: .public)")
                return
            }

            let channelData = outputBuffer.floatChannelData![0]
            let frameCount = Int(outputBuffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
            let normalizedLevel = Self.normalizedLevel(for: samples)

            self.lock.lock()
            self.audioBuffer.append(contentsOf: samples)
            if normalizedLevel > self.smoothedLevel {
                self.smoothedLevel = (self.smoothedLevel * 0.65) + (normalizedLevel * 0.35)
            } else {
                self.smoothedLevel = (self.smoothedLevel * 0.86) + (normalizedLevel * 0.14)
            }
            self.lock.unlock()
        }

        engine.prepare()
        try engine.start()
        isRecording = true
        logger.info("recorder started sampleRate=\(hardwareFormat.sampleRate, format: .fixed(precision: 0)) target=\(self.sampleRate, format: .fixed(precision: 0))")
    }

    func stop() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        lock.lock()
        smoothedLevel = 0
        lock.unlock()
        logger.info("recorder stopped samples=\(self.audioBuffer.count)")
    }

    func getAudio() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return audioBuffer
    }

    func getRecentAudio(seconds: Double = 0.5) -> [Float] {
        let audio = getAudio()
        let sampleCount = Int(seconds * sampleRate)
        if audio.count <= sampleCount { return audio }
        return Array(audio.suffix(sampleCount))
    }

    func isSilent(threshold: Float = -55) -> Bool {
        let audio = getAudio()
        guard !audio.isEmpty else { return true }

        let rms = sqrt(audio.map { $0 * $0 }.reduce(0, +) / Float(audio.count))
        guard rms > 0 else { return true }

        let rmsDB = 20 * log10(rms)
        return rmsDB < threshold
    }

    func currentNormalizedLevel() -> CGFloat {
        lock.lock()
        defer { lock.unlock() }
        return CGFloat(max(0, min(smoothedLevel, 1)))
    }

    var duration: Double {
        lock.lock()
        defer { lock.unlock() }
        return Double(audioBuffer.count) / sampleRate
    }

    private static func normalizedLevel(for samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }

        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
        guard rms > 0 else { return 0 }

        let rmsDB = 20 * log10(rms)
        let floorDB: Float = -52
        let ceilingDB: Float = -8
        let normalized = (rmsDB - floorDB) / (ceilingDB - floorDB)
        return max(0, min(normalized, 1))
    }

    enum AudioRecorderError: Error {
        case converterCreationFailed
    }
}
