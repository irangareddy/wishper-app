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
        let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        // Install tap on input node
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: recordingFormat
        ) { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            guard let self else { return }
            let channelData = buffer.floatChannelData![0]
            let frameCount = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

            self.lock.lock()
            self.audioBuffer.append(contentsOf: samples)
            self.lock.unlock()
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stop() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
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
}
