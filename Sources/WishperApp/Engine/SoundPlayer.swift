import AppKit
import Foundation

final class SoundPlayer {
    var enabled = true

    func startRecording() {
        play("Tink")
    }

    func stopRecording() {
        play("Pop")
    }

    func done() {
        play("Glass")
    }

    func error() {
        play("Basso")
    }

    private func play(_ name: String) {
        guard enabled else { return }
        NSSound(named: name)?.play()
    }
}
