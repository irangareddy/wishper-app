import Combine
import Foundation
import Sparkle
import SwiftUI

/// Bridges Sparkle's `SPUStandardUpdaterController` into SwiftUI.
///
/// Exposes the two pieces of UI state views actually need (whether a check can
/// run right now, and when the last check happened), and republishes the
/// underlying updater's automatic-check preference so a toggle in Settings can
/// bind to it directly.
final class UpdaterManager: ObservableObject {
    @MainActor static let shared = UpdaterManager()

    private let controller: SPUStandardUpdaterController
    private var cancellables: Set<AnyCancellable> = []

    @Published private(set) var canCheckForUpdates: Bool = true
    @Published private(set) var lastUpdateCheckDate: Date?
    @Published var automaticallyChecksForUpdates: Bool = true

    @MainActor
    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        let updater = controller.updater
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
        canCheckForUpdates = updater.canCheckForUpdates

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)

        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastUpdateCheckDate)

        // Write-through: Settings toggle → Sparkle preference.
        $automaticallyChecksForUpdates
            .dropFirst()
            .sink { [weak self] value in
                self?.controller.updater.automaticallyChecksForUpdates = value
            }
            .store(in: &cancellables)
    }

    @MainActor
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
