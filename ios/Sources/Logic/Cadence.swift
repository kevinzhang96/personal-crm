// Whether a friendship is on track, from dates alone. Pure: `now` is an
// argument, so a digest for next Thursday is this function asked about
// next Thursday.

import Foundation

enum ContactStatus: Equatable {
    /// No cadence: kept, never nudged.
    case never
    case snoozed(until: Date)
    case onTrack(daysLeft: Int)
    case dueSoon(daysLeft: Int)
    case overdue(days: Int)

    var isOverdue: Bool {
        if case .overdue = self { return true }
        return false
    }

    var needsAttention: Bool {
        switch self {
        case .overdue, .dueSoon: true
        default: false
        }
    }

    /// Most pressing first: the longest overdue, then the soonest due.
    var urgency: Int {
        switch self {
        case .overdue(let days): 1_000_000 + days
        case .dueSoon(let left): 1_000 - left
        case .onTrack(let left): -left
        case .snoozed: -1_000_000
        case .never: -2_000_000
        }
    }

    /// The two-to-five-character word a row shows.
    var short: String {
        switch self {
        case .never: ""
        case .snoozed: "zz"
        case .onTrack: "ok"
        case .dueSoon(let left): left == 0 ? "today" : "\(left)d"
        case .overdue(let days): "\(days)d over"
        }
    }
}

enum Cadence {
    static func status(
        lastContact: Date?, cadenceDays: Int?, snoozedUntil: Date?, createdAt: Date,
        now: Date, calendar: Calendar = .current
    ) -> ContactStatus {
        guard let cadenceDays, cadenceDays > 0 else { return .never }
        if let snoozedUntil, snoozedUntil > now { return .snoozed(until: snoozedUntil) }
        // Never talked since adding them: the clock started when they were added.
        let anchor = lastContact ?? createdAt
        let deadline = calendar.date(byAdding: .day, value: cadenceDays, to: anchor) ?? anchor
        let daysLeft = Dates.daysBetween(now, deadline, calendar: calendar)
        if daysLeft < 0 { return .overdue(days: -daysLeft) }
        if daysLeft <= dueSoonWindow(cadenceDays) { return .dueSoon(daysLeft: daysLeft) }
        return .onTrack(daysLeft: daysLeft)
    }

    /// A fifth of the cadence, at least a day and at most two weeks: a
    /// weekly friend is "due soon" the day before, a yearly one two weeks
    /// out rather than ten.
    static func dueSoonWindow(_ cadenceDays: Int) -> Int {
        min(max(1, cadenceDays / 5), 14)
    }
}
