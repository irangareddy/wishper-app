import Foundation
import Observation

@Observable
final class StatsTracker {
    var totalWords: Int {
        didSet { UserDefaults.standard.set(totalWords, forKey: "stats.totalWords") }
    }

    var totalTranscriptions: Int {
        didSet { UserDefaults.standard.set(totalTranscriptions, forKey: "stats.totalTranscriptions") }
    }

    var totalRecordingSeconds: Double {
        didSet { UserDefaults.standard.set(totalRecordingSeconds, forKey: "stats.totalRecordingSeconds") }
    }

    var appsUsed: Set<String> {
        didSet { UserDefaults.standard.set(Array(appsUsed), forKey: "stats.appsUsed") }
    }

    var activeDates: Set<String> {
        didSet { UserDefaults.standard.set(Array(activeDates), forKey: "stats.activeDates") }
    }

    var averageWPM: Int {
        guard totalRecordingSeconds > 0 else { return 0 }
        return Int(Double(totalWords) / (totalRecordingSeconds / 60.0))
    }

    var weeklyStreak: Int {
        let calendar = Calendar.current
        let today = Date()
        var streak = 0
        var weekOffset = 0

        while true {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: today),
                  let weekInterval = calendar.dateInterval(of: .weekOfYear, for: weekStart) else { break }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"

            let hasActivity = activeDates.contains { dateStr in
                if let date = formatter.date(from: dateStr) {
                    return weekInterval.contains(date)
                }
                return false
            }

            if hasActivity {
                streak += 1
                weekOffset += 1
            } else if weekOffset == 0 {
                weekOffset += 1
            } else {
                break
            }
        }
        return streak
    }

    init() {
        let ud = UserDefaults.standard
        self.totalWords = ud.integer(forKey: "stats.totalWords")
        self.totalTranscriptions = ud.integer(forKey: "stats.totalTranscriptions")
        self.totalRecordingSeconds = ud.double(forKey: "stats.totalRecordingSeconds")
        self.appsUsed = Set(ud.stringArray(forKey: "stats.appsUsed") ?? [])
        self.activeDates = Set(ud.stringArray(forKey: "stats.activeDates") ?? [])
    }

    func recordTranscription(text: String, durationSeconds: Double, appName: String) {
        let words = text.split(separator: " ").count
        totalWords += words
        totalTranscriptions += 1
        totalRecordingSeconds += durationSeconds
        appsUsed.insert(appName)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        activeDates.insert(formatter.string(from: Date()))
    }
}
