import ActivityKit
import Foundation

/// What the Live Activity (Lock Screen + Dynamic Island) shows.
struct FocusAttributes: ActivityAttributes {
    struct Row: Codable, Hashable {
        var name: String
        var seconds: Double
    }

    struct ContentState: Codable, Hashable {
        /// The app open right now, or today's most-used app.
        var appName: String
        /// Today's total for that app at the last update.
        var seconds: Double
        /// Set while the app is open; the timer then ticks on its own from here.
        var liveSince: Date?
        var modeName: String?
        var top: [Row]
        var note: String?
    }
}

enum Fmt {
    /// "1h 05m", "42m", "0m"
    static func duration(_ seconds: Double) -> String {
        let m = Int(max(seconds, 0) / 60)
        return m >= 60 ? String(format: "%dh %02dm", m / 60, m % 60) : "\(m)m"
    }

    /// Rounded down to 5-minute steps: 0m, 5m, 10m, 15m...
    static func stepped(_ seconds: Double) -> String {
        duration(Double(Int(max(seconds, 0) / 300) * 300))
    }

    /// Short enough for the Dynamic Island: "Instagram" -> "Insta"
    static func short(_ name: String) -> String {
        name.count <= 6 ? name : String(name.prefix(5))
    }
}
