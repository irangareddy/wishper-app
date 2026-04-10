import AVFoundation
import Foundation

@Observable
final class AudioRecorder {
    private var engine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let lock = NSLock()
    private(set) var isRecording = false

    let sampleRate: Double = 16000

    func start() throws {
        guard !isRecording else { return }
        audioBuffer = []

        let inputNode = engine.inputNode
        // Use the hardware's native format — don't force 16kHz
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        print("[wishper] Mic hardware format: \(hardwareFormat)")

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
                print("[wishper] Audio conversion error: \(error)")
                return
            }

            let channelData = outputBuffer.floatChannelData![0]
            let frameCount = Int(outputBuffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

            self.lock.lock()
            self.audioBuffer.append(contentsOf: samples)
            self.lock.unlock()
        }

        engine.prepare()
        try engine.start()
        isRecording = true
        print("[wishper] Recording started (\(hardwareFormat.sampleRate)Hz -> \(sampleRate)Hz)")
    }

    func stop() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        print("[wishper] Recording stopped, \(audioBuffer.count) samples captured")
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

    var duration: Double {
        lock.lock()
        defer { lock.unlock() }
        return Double(audioBuffer.count) / sampleRate
    }

    enum AudioRecorderError: Error {
        case converterCreationFailed
    }
}
