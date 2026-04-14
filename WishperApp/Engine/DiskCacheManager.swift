import Foundation

enum DiskCacheManager {

    struct CachedModel: Identifiable {
        let name: String
        let sizeBytes: Int
        let path: URL
        var id: URL { path }
    }

    // MARK: - Known cache directories

    /// ASR models cached by speech-swift (HuggingFaceDownloader defaults to ~/Library/Caches/qwen3-speech/).
    private static var asrCacheBase: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("qwen3-speech", isDirectory: true)
    }

    /// LLM models cached by swift-transformers HubApi (defaults to ~/Documents/huggingface/).
    private static var llmCacheBase: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("huggingface", isDirectory: true)
    }

    static var allCacheBases: [URL] { [asrCacheBase, llmCacheBase] }

    // MARK: - Public API

    static func cacheSizeBytes() async -> Int {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let total = allCacheBases.reduce(0) { sum, base in
                    sum + directorySize(at: base)
                }
                continuation.resume(returning: total)
            }
        }
    }

    static func listCachedModels() async -> [CachedModel] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var models: [CachedModel] = []
                let fm = FileManager.default

                for base in allCacheBases {
                    // Models are stored under models/<org>/<model>
                    let modelsDir = base.appendingPathComponent("models", isDirectory: true)
                    guard let orgDirs = try? fm.contentsOfDirectory(
                        at: modelsDir,
                        includingPropertiesForKeys: nil,
                        options: .skipsHiddenFiles
                    ) else { continue }

                    for orgDir in orgDirs {
                        guard let modelDirs = try? fm.contentsOfDirectory(
                            at: orgDir,
                            includingPropertiesForKeys: nil,
                            options: .skipsHiddenFiles
                        ) else { continue }

                        for modelDir in modelDirs {
                            let name = "\(orgDir.lastPathComponent)/\(modelDir.lastPathComponent)"
                            let size = directorySize(at: modelDir)
                            if size > 0 {
                                models.append(CachedModel(name: name, sizeBytes: size, path: modelDir))
                            }
                        }
                    }
                }

                continuation.resume(returning: models.sorted { $0.sizeBytes > $1.sizeBytes })
            }
        }
    }

    static func deleteCache(at path: URL) throws {
        try FileManager.default.removeItem(at: path)
    }

    static func clearAllCaches() throws {
        for base in allCacheBases {
            let modelsDir = base.appendingPathComponent("models", isDirectory: true)
            if FileManager.default.fileExists(atPath: modelsDir.path) {
                try FileManager.default.removeItem(at: modelsDir)
            }
        }
    }

    static func formattedSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // MARK: - Private

    private static func directorySize(at url: URL) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize
            {
                total += size
            }
        }
        return total
    }
}
