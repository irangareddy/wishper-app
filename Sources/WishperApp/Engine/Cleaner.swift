import Foundation
import MLXLLM
import MLXLMCommon

actor Cleaner {
    private var model: ModelContainer?
    private let modelName: String
    private let maxTokens: Int
    var enabled: Bool

    init(model: String = "mlx-community/Qwen3-0.6B-4bit", maxTokens: Int = 256, enabled: Bool = true) {
        self.modelName = model
        self.maxTokens = maxTokens
        self.enabled = enabled
    }

    func loadModel() async throws {
        guard enabled else { return }
        print("[wishper] LLM: Loading \(modelName)...")
        let configuration = ModelConfiguration(id: modelName)
        model = try await LLMModelFactory.shared.loadContainer(configuration: configuration) { progress in
            let pct = Int(progress.fractionCompleted * 100)
            print("[wishper] LLM: \(pct)%")
        }
        print("[wishper] LLM: Model loaded")
    }

    func clean(rawText: String, appContext: String = "") async throws -> String {
        guard enabled, let model else { return rawText }
        guard !rawText.isEmpty else { return "" }

        let toneLine = appContext.isEmpty ? "" : "- Tone: \(appContext)\n"
        let systemPrompt = """
        You are a dictation cleanup assistant. Your ONLY job is to clean raw dictated text. /no_think

        Rules:
        - Remove ALL filler words: um, uh, like, you know, so, basically, actually, I mean, kind of, sort of
        - Remove false starts and repeated words
        - Fix grammar and punctuation
        - Remove leading fillers (do NOT start output with "So," or "Like,")
        - Keep the FULL original meaning — do not summarize, truncate, or shorten
        - Keep ALL sentences — do not drop or merge sentences
        - Output ONLY the cleaned text, nothing else
        - Do NOT think, reason, or explain — just output the cleaned text
        - Do NOT explain, comment, or think out loud
        - The output should be roughly the same length as the input
        \(toneLine)
        """

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": rawText],
        ]

        var outputText = ""
        let stream = try await model.perform { context in
            let input = try await context.processor.prepare(input: .init(messages: messages))
            return try MLXLMCommon.generate(
                input: input,
                parameters: .init(temperature: 0.0),
                context: context
            )
        }

        var tokenCount = 0
        for try await result in stream {
            outputText += result.chunk ?? ""
            tokenCount += 1
            if tokenCount >= maxTokens { break }
        }

        var output = outputText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip all <think> content — closed or unclosed
        if let thinkStart = output.range(of: "<think>") {
            if let thinkEnd = output.range(of: "</think>") {
                // Closed tag — remove the block and keep text after
                let afterThink = output[thinkEnd.upperBound...]
                output = String(afterThink)
            } else {
                // Unclosed tag (thinking overflowed max tokens) — keep text before
                output = String(output[..<thinkStart.lowerBound])
            }
        }
        // Strip leading fillers
        let fillerPattern = "^(So,?\\s*|Like,?\\s*|Well,?\\s*|I mean,?\\s*)"
        if let regex = try? NSRegularExpression(pattern: fillerPattern, options: .caseInsensitive) {
            output = regex.stringByReplacingMatches(
                in: output, range: NSRange(output.startIndex..., in: output), withTemplate: ""
            )
        }

        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? rawText : output
    }
}
