import Foundation
import Qwen3ASR

actor Transcriber {
    private var model: Qwen3ASRModel?
    private let modelId: String

    init(model: String = "aufklarer/Qwen3-ASR-0.6B-MLX-4bit") {
        self.modelId = model
    }

    func loadModel() async throws {
        model = try await Qwen3ASRModel.fromPretrained(modelId: modelId) { progress, status in
            print("[wishper] ASR model: [\(Int(progress * 100))%] \(status)")
        }
    }

    func transcribe(audioArray: [Float]) async throws -> String {
        guard let model else {
            throw TranscriberError.modelNotLoaded
        }

        let result = model.transcribe(audio: audioArray, sampleRate: 16000)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum TranscriberError: Error {
        case modelNotLoaded
    }
}
