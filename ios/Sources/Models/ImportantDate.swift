// A yearly date on a friend's calendar — birthday first of all. The year
// is optional because most people don't know their friends' birth years.

import Foundation
import SwiftData

@Model
final class ImportantDate {
    var id: UUID = UUID()
    var label: String = ""
    var month: Int = 1
    var day: Int = 1
    var year: Int?
    var remind: Bool = true
    var friend: Friend?

    init(label: String, month: Int, day: Int, year: Int? = nil, remind: Bool = true) {
        self.label = label
        self.month = month
        self.day = day
        self.year = year
        self.remind = remind
    }
}

extension ImportantDate {
    static let birthdayLabel = "Birthday"

    /// The next time this date comes round, on or after `now`'s day.
    func next(after now: Date, calendar: Calendar = .current) -> Date? {
        Dates.nextOccurrence(month: month, day: day, after: now, calendar: calendar)
    }

    /// Age turned on the next occurrence, when the year is known.
    func ageTurning(on date: Date, calendar: Calendar = .current) -> Int? {
        guard let year else { return nil }
        return calendar.component(.year, from: date) - year
    }
}
