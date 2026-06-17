import Foundation

/// Lightweight usage stats for the home-screen dashboard, persisted in
/// UserDefaults: how many presentations were run and their total/average length.
enum Stats {
    static let didChange = Notification.Name("StatsDidChange")
    private static let countKey = "stats.sessionCount"
    private static let totalKey = "stats.totalSeconds"

    static var count: Int { UserDefaults.standard.integer(forKey: countKey) }
    static var totalSeconds: Double { UserDefaults.standard.double(forKey: totalKey) }
    static var averageSeconds: Double { count > 0 ? totalSeconds / Double(count) : 0 }

    /// Records a finished presentation session (ignores trivially short ones).
    static func record(seconds: Double) {
        guard seconds >= 2 else { return }
        let defaults = UserDefaults.standard
        defaults.set(count + 1, forKey: countKey)
        defaults.set(totalSeconds + seconds, forKey: totalKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// "MM:SS" or "H:MM:SS" for longer spans.
    static func format(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
