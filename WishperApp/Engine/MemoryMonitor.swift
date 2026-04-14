import Combine
import Dispatch
import Foundation
import MLX
import OSLog

enum MemoryPressureLevel: String {
    case nominal
    case warning
    case critical

    var displayString: String { rawValue.capitalized }
}

@MainActor
final class MemoryMonitor: ObservableObject {
    private let logger = WishperLog.memory
    private var pressureSource: DispatchSourceMemoryPressure?
    private var pollingTask: Task<Void, Never>?

    // MARK: - Published stats

    @Published private(set) var currentResidentMB: Int = 0
    @Published private(set) var mlxActiveMemoryMB: Int = 0
    @Published private(set) var mlxCacheMemoryMB: Int = 0
    @Published private(set) var mlxPeakMemoryMB: Int = 0
    @Published private(set) var pressureLevel: MemoryPressureLevel = .nominal
    @Published var asrModelLoaded = false
    @Published var llmModelLoaded = false

    /// Called when the system signals memory pressure and the LLM should be shed.
    var shedLLM: (() -> Void)?

    // MARK: - Lifecycle

    init() {
        setupMemoryPressureSource()
    }

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refreshStats()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        logger.info("memory polling started")
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        logger.info("memory polling stopped")
    }

    // MARK: - Memory pressure dispatch source

    private func setupMemoryPressureSource() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = source.data

            Task { @MainActor in
                if event.contains(.critical) {
                    self.handlePressure(.critical)
                } else if event.contains(.warning) {
                    self.handlePressure(.warning)
                }
            }
        }

        source.resume()
        pressureSource = source
    }

    private func handlePressure(_ level: MemoryPressureLevel) {
        pressureLevel = level
        refreshStats()

        logger.warning(
            "memory pressure level=\(level.rawValue) resident=\(self.currentResidentMB)MB mlxActive=\(self.mlxActiveMemoryMB)MB mlxCache=\(self.mlxCacheMemoryMB)MB"
        )

        shedLLM?()

        if level == .critical {
            Memory.clearCache()
            logger.warning("cleared MLX cache due to critical memory pressure")
        }
    }

    // MARK: - Stats

    private func refreshStats() {
        currentResidentMB = Self.residentMemoryBytes() / (1024 * 1024)
        mlxActiveMemoryMB = Memory.activeMemory / (1024 * 1024)
        mlxCacheMemoryMB = Memory.cacheMemory / (1024 * 1024)
        mlxPeakMemoryMB = Memory.peakMemory / (1024 * 1024)

        // Reset pressure to nominal if no recent system event
        // (DispatchSource only fires on transitions, so we clear after stats look healthy)
        if pressureLevel != .nominal, currentResidentMB < 400 {
            pressureLevel = .nominal
        }
    }

    private static func residentMemoryBytes() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }

    deinit {
        pressureSource?.cancel()
    }
}
