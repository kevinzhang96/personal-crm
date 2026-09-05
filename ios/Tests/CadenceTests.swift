// The whole nudge rule, at the day boundaries where it matters.

import Foundation
import Testing
@testable import Tend

struct CadenceTests {
    let calendar = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 1_788_000_000) // 2026-08-29-ish, midday-ish

    func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: now)! }

    @Test("a friend talked to yesterday on a monthly cadence is on track")
    func onTrack() {
        let status = Cadence.status(lastContact: day(-1), cadenceDays: 30, snoozedUntil: nil, createdAt: day(-100), now: now, calendar: calendar)
        #expect(status == .onTrack(daysLeft: 29))
    }

    @Test("the day the cadence runs out is due today, and the day after is one day over")
    func boundary() {
        #expect(Cadence.status(lastContact: day(-30), cadenceDays: 30, snoozedUntil: nil, createdAt: day(-100), now: now, calendar: calendar) == .dueSoon(daysLeft: 0))
        #expect(Cadence.status(lastContact: day(-31), cadenceDays: 30, snoozedUntil: nil, createdAt: day(-100), now: now, calendar: calendar) == .overdue(days: 1))
    }

    @Test("due-soon is a fifth of the cadence, between a day and two weeks")
    func window() {
        #expect(Cadence.dueSoonWindow(7) == 1)
        #expect(Cadence.dueSoonWindow(30) == 6)
        #expect(Cadence.dueSoonWindow(365) == 14)
        #expect(Cadence.status(lastContact: day(-25), cadenceDays: 30, snoozedUntil: nil, createdAt: day(-100), now: now, calendar: calendar) == .dueSoon(daysLeft: 5))
    }

    @Test("never talked: the clock started when they were added")
    func neverTalked() {
        #expect(Cadence.status(lastContact: nil, cadenceDays: 7, snoozedUntil: nil, createdAt: day(-10), now: now, calendar: calendar) == .overdue(days: 3))
    }

    @Test("no cadence means never nudged, whatever the dates")
    func noCadence() {
        #expect(Cadence.status(lastContact: day(-900), cadenceDays: nil, snoozedUntil: nil, createdAt: day(-1000), now: now, calendar: calendar) == .never)
        #expect(Cadence.status(lastContact: nil, cadenceDays: 0, snoozedUntil: nil, createdAt: day(-1000), now: now, calendar: calendar) == .never)
    }

    @Test("snooze hides an overdue friend until it passes, then they are overdue again")
    func snooze() {
        let until = day(5)
        #expect(Cadence.status(lastContact: day(-60), cadenceDays: 30, snoozedUntil: until, createdAt: day(-100), now: now, calendar: calendar) == .snoozed(until: until))
        #expect(Cadence.status(lastContact: day(-60), cadenceDays: 30, snoozedUntil: until, createdAt: day(-100), now: day(6), calendar: calendar) == .overdue(days: 36))
    }

    @Test("urgency orders the most overdue first, then the soonest due")
    func urgency() {
        let statuses: [ContactStatus] = [.onTrack(daysLeft: 10), .overdue(days: 2), .dueSoon(daysLeft: 1), .overdue(days: 40), .never, .snoozed(until: now)]
        let sorted = statuses.sorted { $0.urgency > $1.urgency }
        #expect(sorted == [.overdue(days: 40), .overdue(days: 2), .dueSoon(daysLeft: 1), .onTrack(daysLeft: 10), .snoozed(until: now), .never])
    }
}

struct DatesTests {
    let calendar = Calendar(identifier: .gregorian)

    @Test("next occurrence rolls into next year once the day has passed")
    func nextOccurrence() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 15))!
        let later = Dates.nextOccurrence(month: 9, day: 5, after: now, calendar: calendar)!
        #expect(calendar.dateComponents([.year, .month, .day], from: later) == DateComponents(year: 2026, month: 9, day: 5), "today counts")
        let passed = Dates.nextOccurrence(month: 9, day: 4, after: now, calendar: calendar)!
        #expect(calendar.component(.year, from: passed) == 2027)
    }

    @Test("ago and until speak in the units a row can afford")
    func words() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 12))!
        func d(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: now)! }
        #expect(Dates.ago(now, now: now, calendar: calendar) == "today")
        #expect(Dates.ago(d(-1), now: now, calendar: calendar) == "yesterday")
        #expect(Dates.ago(d(-13), now: now, calendar: calendar) == "13d")
        #expect(Dates.ago(d(-21), now: now, calendar: calendar) == "3w")
        #expect(Dates.ago(d(-90), now: now, calendar: calendar) == "3mo")
        #expect(Dates.ago(d(-800), now: now, calendar: calendar) == "2y")
        #expect(Dates.until(d(1), now: now, calendar: calendar) == "tomorrow")
        #expect(Dates.until(d(4), now: now, calendar: calendar) == "in 4d")
        #expect(Dates.until(d(-3), now: now, calendar: calendar) == "3d ago")
    }
}
