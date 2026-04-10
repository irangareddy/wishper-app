import AppKit
import Foundation

struct AppContext {
    static func getActiveApp() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
    }
    
    static func getTone(for appName: String) -> String {
        let name = appName.lowercased()
        
        let tones: [(apps: [String], tone: String)] = [
            (["slack", "discord"], "casual, concise messaging"),
            (["mail", "outlook"], "professional, complete sentences"),
            (["cursor", "vs code", "visual studio code", "xcode", "terminal", "iterm", "iterm2"], "technical, code-aware"),
            (["notes", "obsidian"], "clear, organized notes"),
            (["safari", "chrome", "arc"], "general web content"),
            (["messages"], "casual, brief"),
        ]
        
        for (apps, tone) in tones {
            if apps.contains(name) { return tone }
        }
        return "clear and natural"
    }
}
