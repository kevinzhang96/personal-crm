// Calendar arithmetic the rest of Logic shares. Whole days, in the
// calendar given, so a conversation at 23:50 and a check at 00:10 are a
// day apart rather than twenty minutes.

import Foundation

enum Dates {
    /// Whole days from `a`'s day to `b`'s day; negative when `b` is earlier.
    static func daysBetween(_ a: Date, _ b: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)
        ).day ?? 0
    }

    /// The next month/day on or after `now`'s day. A 29 February in a
    /// common year lands on 1 March, which is where the calendar puts it.
    static func nextOccurrence(month: Int, day: Int, after now: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        let year = calendar.component(.year, from: today)
        for candidate in year...(year + 1) {
            var parts = DateComponents()
            parts.year = candidate
            parts.month = month
            parts.day = day
            if let date = calendar.date(from: parts), date >= today { return date }
        }
        return nil
    }

    /// `day` at a wall-clock time.
    static func at(hour: Int, minute: Int = 0, on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// "today", "yesterday", "3d", "2w", "4mo", "1y" — how long ago, as a
    /// row can afford to say it.
    static func ago(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = daysBetween(date, now, calendar: calendar)
        switch days {
        case ..<0: return "soon"
        case 0: return "today"
        case 1: return "yesterday"
        case 2..<14: return "\(days)d"
        case 14..<60: return "\(days / 7)w"
        case 60..<365: return "\(days / 30)mo"
        default: return "\(days / 365)y"
        }
    }

    /// `ago`, as a phrase: "today", "yesterday", "3d ago".
    static func since(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let word = ago(date, now: now, calendar: calendar)
        return ["today", "yesterday", "soon"].contains(word) ? word : word + " ago"
    }

    /// "today", "tomorrow", "in 3d", "3d ago" — how far off, for a due date.
    static func until(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = daysBetween(now, date, calendar: calendar)
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case 2...: return "in \(days)d"
        case -1: return "yesterday"
        default: return "\(-days)d ago"
        }
    }
}
