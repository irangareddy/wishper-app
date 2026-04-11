import Foundation
import OSLog

enum WishperLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "in.irangareddy.Wishper-App"
    static let voicePipeline = Logger(subsystem: subsystem, category: "voicePipeline")
}
