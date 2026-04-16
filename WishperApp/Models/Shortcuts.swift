import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Hold to record, release to transcribe and paste. (fn also works via FnKeyDetector)
    static let pushToTalk = Self("pushToTalk", default: .init(.r, modifiers: [.command, .shift]))

    /// Press to start hands-free recording.
    static let handsFree = Self("handsFree", default: .init(.d, modifiers: [.command, .shift]))

    /// Paste the last transcript into the active app.
    static let pasteLastTranscript = Self("pasteLastTranscript", default: .init(.v, modifiers: [.command, .control]))

    /// Cancel current recording.
    static let cancelRecording = Self("cancelRecording", default: .init(.period, modifiers: [.command]))
}
