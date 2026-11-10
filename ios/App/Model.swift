import Foundation

enum AppCategory: String, Codable, CaseIterable, Identifiable {
    case social, video, gaming, work, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .social: return "Social media"
        case .video: return "Video & streaming"
        case .gaming: return "Games"
        case .work: return "Work & school"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .social: return "bubble.left.and.bubble.right.fill"
        case .video: return "play.rectangle.fill"
        case .gaming: return "gamecontroller.fill"
        case .work: return "briefcase.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }

    /// Best guess for an app name typed into a Shortcut. Can be changed in the app.
    static func guess(_ name: String) -> AppCategory {
        let n = name.lowercased()
        let table: [(AppCategory, [String])] = [
            (.social, ["instagram", "tiktok", "snapchat", "twitter", "facebook", "threads", "reddit",
                       "bereal", "pinterest", "discord", "tumblr", "linkedin", "messenger"]),
            (.video, ["youtube", "netflix", "hulu", "disney", "twitch", "prime video", "crunchyroll", "hbo"]),
            (.gaming, ["roblox", "minecraft", "fortnite", "clash", "pubg", "brawl", "genshin", "candy crush",
                       "call of duty", "pokemon", "among us", "subway surfers"]),
            (.work, ["notion", "docs", "sheets", "slides", "gmail", "outlook", "slack", "canvas", "teams",
                     "zoom", "calendar", "word", "excel", "github", "chatgpt", "claude"]),
        ]
        for (category, words) in table where words.contains(where: { n.contains($0) }) {
            return category
        }
        return .other
    }
}

struct TrackedApp: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Must match the name typed into the Shortcuts automation (case doesn't matter).
    var name: String
    var category: AppCategory

    var key: String { id.uuidString }
}

struct FocusMode: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var symbol: String
    var blocks: Set<AppCategory>

    var summary: String {
        if blocks.isEmpty { return "Blocks nothing" }
        let names = AppCategory.allCases.filter { blocks.contains($0) }.map(\.label)
        return "Blocks " + names.joined(separator: ", ")
    }

    static let defaults: [FocusMode] = [
        FocusMode(id: "nosocial", name: "No social media", symbol: "person.2.slash", blocks: [.social]),
        FocusMode(id: "nogaming", name: "No gaming", symbol: "gamecontroller", blocks: [.gaming]),
        FocusMode(id: "work", name: "Work", symbol: "briefcase", blocks: [.social, .gaming, .video]),
        FocusMode(id: "fun", name: "Fun", symbol: "party.popper", blocks: []),
        FocusMode(id: "relax", name: "Relax", symbol: "leaf", blocks: [.work, .social]),
    ]
}

struct ScheduleBlock: Codable, Identifiable, Equatable {
    var id = UUID()
    var modeID: String
    /// Minutes after midnight.
    var start: Int
    var end: Int
    /// Calendar weekdays: 1 = Sunday ... 7 = Saturday.
    var days: Set<Int>

    func contains(_ date: Date) -> Bool {
        let m = Clock.minutes(date)
        let today = Calendar.current.component(.weekday, from: date)
        let yesterday = today == 1 ? 7 : today - 1
        if start < end {
            return days.contains(today) && m >= start && m < end
        }
        // Overnight block, e.g. 10 PM - 1 AM.
        return (days.contains(today) && m >= start) || (days.contains(yesterday) && m < end)
    }

    var daysLabel: String {
        switch days {
        case Set(1...7): return "Every day"
        case Set([2, 3, 4, 5, 6]): return "Weekdays"
        case Set([1, 7]): return "Weekends"
        default:
            let symbols = Calendar.current.shortWeekdaySymbols
            return days.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
        }
    }
}

struct DayUsage: Codable, Equatable {
    var day: String
    /// Finished time per app key.
    var seconds: [String: Double] = [:]
    /// Apps open right now, and since when.
    var openSince: [String: Date] = [:]
    /// How many times each app was blocked today.
    var blocked: [String: Int] = [:]
}

struct AppState: Codable, Equatable {
    var apps: [TrackedApp] = [
        TrackedApp(name: "Instagram", category: .social),
        TrackedApp(name: "TikTok", category: .social),
        TrackedApp(name: "YouTube", category: .video),
    ]
    var modes: [FocusMode] = FocusMode.defaults
    var blocks: [ScheduleBlock] = []
    var scheduleOn = false
    /// A mode turned on by hand. Wins over the schedule.
    var manualModeID: String?
    var liveOn = true
    var liveStarted: Date?
    var today = DayUsage(day: Clock.dayKey(.now))
}

enum Clock {
    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func minutes(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func date(_ minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: (minutes / 60) % 24, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    /// "9:00 AM"
    static func label(_ minutes: Int) -> String {
        date(minutes).formatted(date: .omitted, time: .shortened)
    }
}
