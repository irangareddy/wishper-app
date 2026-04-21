import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers

/// Friction-free support utilities for users who hit a bug.
///
/// - `reportBugURL` produces a GitHub new-issue URL with the bug template
///   pre-selected and the version/macOS/hardware block pre-filled, so
///   users land on a partly-completed form in ~2 clicks.
/// - `exportDiagnostics` collects the last hour of our own OSLog entries
///   plus a system header, presents an `NSSavePanel`, and writes a plain
///   text file the user can attach to their GitHub issue.
///
/// No network calls are made. Everything happens locally.
@MainActor
enum SupportTools {
    private static let repoSlug = "irangareddy/wishper-app"

    // MARK: - Report a bug

    /// A GitHub "new issue" URL with the bug template pre-filled.
    static var reportBugURL: URL {
        var components = URLComponents(string: "https://github.com/\(repoSlug)/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug.yml"),
            URLQueryItem(name: "version", value: versionLine()),
            URLQueryItem(name: "macos", value: macOSLine()),
            URLQueryItem(name: "hardware", value: hardwareLine()),
        ]
        return components.url!
    }

    static func openBugReport() {
        NSWorkspace.shared.open(reportBugURL)
    }

    // MARK: - Send feedback

    /// A GitHub Discussions "new discussion" URL, targeting the Ideas
    /// category so feedback gets classified correctly out of the gate.
    static var sendFeedbackURL: URL {
        URL(string: "https://github.com/\(repoSlug)/discussions/new?category=ideas")!
    }

    static func openFeedback() {
        NSWorkspace.shared.open(sendFeedbackURL)
    }

    /// Opens the user's default mail client with a pre-filled message.
    /// Useful fallback for users without a GitHub account.
    static func openEmail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "wishper@irangareddy.in"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Wishper feedback"),
            URLQueryItem(name: "body", value: """


                ───
                App:       \(versionLine())
                macOS:     \(macOSLine())
                Hardware:  \(hardwareLine())
                """),
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Export diagnostics

    /// Prompts the user for a destination, then writes a plain-text
    /// diagnostics bundle. Safe to call from a SwiftUI button action.
    static func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.title = "Export Wishper Diagnostics"
        panel.nameFieldStringValue = defaultFileName()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            let bundle = await diagnosticsBundle()
            do {
                try bundle.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not save diagnostics"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    // MARK: - Bundle construction

    private static func defaultFileName() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HHmmss"
        return "wishper-diagnostics-\(df.string(from: Date())).txt"
    }

    /// Compose the full diagnostics text. Runs in a background task because
    /// OSLogStore reads can take a moment on large log volumes.
    static func diagnosticsBundle() async -> String {
        var lines: [String] = []
        lines.append("Wishper Diagnostics")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append(String(repeating: "─", count: 48))
        lines.append("")
        lines.append("App:       \(versionLine())")
        lines.append("macOS:     \(macOSLine())")
        lines.append("Hardware:  \(hardwareLine())")
        lines.append("Locale:    \(Locale.current.identifier)")
        lines.append("")
        lines.append(String(repeating: "─", count: 48))
        lines.append("Recent log entries (last hour)")
        lines.append(String(repeating: "─", count: 48))

        let logLines = await collectRecentLogs()
        if logLines.isEmpty {
            lines.append("(no entries — OSLogStore returned nothing for this process)")
        } else {
            lines.append(contentsOf: logLines)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Reads our subsystem's log entries from the past hour.
    /// Uses `OSLogStore` (macOS 12+) scoped to the current process, so we
    /// never surface other apps' logs.
    private static func collectRecentLogs() async -> [String] {
        await Task.detached(priority: .utility) { () -> [String] in
            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                let since = Date().addingTimeInterval(-3600)
                let position = store.position(date: since)
                let subsystem = Bundle.main.bundleIdentifier ?? "in.irangareddy.Wishper-App"
                let predicate = NSPredicate(format: "subsystem == %@", subsystem)
                let entries = try store.getEntries(at: position, matching: predicate)

                var out: [String] = []
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                for entry in entries {
                    guard let logEntry = entry as? OSLogEntryLog else { continue }
                    let level = Self.levelLabel(for: logEntry.level)
                    let stamp = formatter.string(from: logEntry.date)
                    out.append("[\(stamp)] \(level) [\(logEntry.category)] \(logEntry.composedMessage)")
                }
                return out
            } catch {
                return ["(failed to read OSLog: \(error.localizedDescription))"]
            }
        }.value
    }

    nonisolated private static func levelLabel(for level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug:  return "DEBUG"
        case .info:   return "INFO "
        case .notice: return "NOTE "
        case .error:  return "ERROR"
        case .fault:  return "FAULT"
        case .undefined: return "----"
        @unknown default: return "???? "
        }
    }

    // MARK: - System info helpers

    static func versionLine() -> String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    static func macOSLine() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Apple-silicon chip family + total RAM. Uses `sysctl` directly so we
    /// don't need to ship any third-party hardware detection code.
    static func hardwareLine() -> String {
        let chip = sysctlString("machdep.cpu.brand_string") ?? "unknown chip"
        let memBytes = ProcessInfo.processInfo.physicalMemory
        let gb = Double(memBytes) / 1_073_741_824.0
        let ramString = String(format: "%.0f GB", gb.rounded())
        let model = sysctlString("hw.model") ?? "Mac"
        return "\(model), \(chip), \(ramString)"
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
