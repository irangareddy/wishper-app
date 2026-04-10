import AppKit
import Foundation

final class TextInjector {
    func inject(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Try AppleScript paste first
        let script = NSAppleScript(source: """
            tell application "System Events"
                keystroke "v" using command down
            end tell
        """)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)

        if error != nil {
            // Paste failed — text is on clipboard, user can Cmd+V manually
            print("[wishper] Auto-paste unavailable (needs Accessibility). Text copied to clipboard — press Cmd+V to paste.")
            return true  // Still "success" — text is on clipboard
        }

        return true
    }
}
