import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Hold to record, release to transcribe and paste.
    static let pushToTalk = Self("pushToTalk", default: .init(.r, modifiers: [.command, .shift]))

    /// Press to start recording, press again to stop.
    static let handsFree = Self("handsFree", default: .init(.space, modifiers: [.control]))

    /// Paste the last transcript into the active app.
    static let pasteLastTranscript = Self("pasteLastTranscript", default: .init(.v, modifiers: [.command, .control]))
}
