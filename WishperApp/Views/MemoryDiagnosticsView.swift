import SwiftUI

struct MemoryDiagnosticsView: View {
    @ObservedObject var memoryMonitor: MemoryMonitor
    @State private var cachedModels: [DiskCacheManager.CachedModel] = []
    @State private var totalCacheSize: Int = 0
    @State private var showDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Runtime Memory") {
                LabeledContent("Process Resident") {
                    Text("\(memoryMonitor.currentResidentMB) MB")
                        .monospacedDigit()
                }
                LabeledContent("MLX Active") {
                    Text("\(memoryMonitor.mlxActiveMemoryMB) MB")
                        .monospacedDigit()
                }
                LabeledContent("MLX Cache") {
                    Text("\(memoryMonitor.mlxCacheMemoryMB) MB")
                        .monospacedDigit()
                }
                LabeledContent("MLX Peak") {
                    Text("\(memoryMonitor.mlxPeakMemoryMB) MB")
                        .monospacedDigit()
                }
                LabeledContent("Memory Pressure") {
                    Text(memoryMonitor.pressureLevel.displayString)
                        .foregroundStyle(pressureColor)
                }
            }

            Section("Loaded Models") {
                LabeledContent("ASR Model") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(memoryMonitor.asrModelLoaded ? .green : .gray)
                            .frame(width: 8, height: 8)
                        Text(memoryMonitor.asrModelLoaded ? "Loaded" : "Unloaded")
                    }
                }
                LabeledContent("LLM Model") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(memoryMonitor.llmModelLoaded ? .green : .gray)
                            .frame(width: 8, height: 8)
                        Text(memoryMonitor.llmModelLoaded ? "Loaded" : "Unloaded")
                    }
                }
            }

            Section("Disk Cache") {
                LabeledContent("Total Cache Size") {
                    Text(DiskCacheManager.formattedSize(totalCacheSize))
                        .monospacedDigit()
                }

                if cachedModels.isEmpty {
                    Text("No cached models found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cachedModels) { model in
                        LabeledContent(model.name) {
                            Text(DiskCacheManager.formattedSize(model.sizeBytes))
                                .monospacedDigit()
                        }
                    }
                }

                Button("Clear All Caches") {
                    showDeleteConfirmation = true
                }
                .disabled(totalCacheSize == 0)
                .confirmationDialog(
                    "Clear all cached models?",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear", role: .destructive) {
                        clearCaches()
                    }
                } message: {
                    Text(
                        "This will delete \(DiskCacheManager.formattedSize(totalCacheSize)) of cached model files. Models will be re-downloaded on next use."
                    )
                }
            }
        }
        .formStyle(.grouped)
        .task { await refreshCacheInfo() }
    }

    private var pressureColor: Color {
        switch memoryMonitor.pressureLevel {
        case .nominal: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    private func refreshCacheInfo() async {
        totalCacheSize = await DiskCacheManager.cacheSizeBytes()
        cachedModels = await DiskCacheManager.listCachedModels()
    }

    private func clearCaches() {
        try? DiskCacheManager.clearAllCaches()
        Task { await refreshCacheInfo() }
    }
}
