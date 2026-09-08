// What goes on the calendar, when it moves, and what a reconcile does —
// against a dictionary standing in for EventKit.

import Foundation
import Testing
@testable import Tend

struct CalendarSyncTests {
    let calendar = Calendar(identifier: .gregorian)
    // Saturday 2026-09-05, 15:00.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 15))! }
    func day(_ month: Int, _ day: Int, hour: Int = 0) -> Date { calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))! }
    func ymd(_ date: Date) -> DateComponents { calendar.dateComponents([.year, .month, .day], from: date) }

    let priya = UUID(), sam = UUID(), entry = UUID(), reminder = UUID()
    var all: CalendarSyncSettings { CalendarSyncSettings(enabled: true, followUps: true, logs: true, catchUps: true) }

    var input: CalendarPlanInput {
        CalendarPlanInput(
            friends: [
                .init(id: priya, name: "Priya", lastContact: day(8, 20), createdAt: day(1, 1), cadenceDays: 30, snoozedUntil: nil, archived: false),
                .init(id: sam, name: "Sam", lastContact: nil, createdAt: day(9, 1), cadenceDays: 7, snoozedUntil: nil, archived: false),
            ],
            reminders: [.init(id: reminder, title: "Ask how the interview went", due: day(9, 11, hour: 9), done: false, friendName: "Priya", note: "Figma")],
            entries: [.init(id: entry, date: day(8, 20, hour: 18), kind: "Call", friendNames: ["Priya"], text: "Long call about the interview.")])
    }

    /// A calendar that is a dictionary.
    final class Store: CalendarStore {
        var items: [String: CalendarItem] = [:]
        var next = 0
        var log: [String] = []
        func item(_ id: String) throws -> CalendarItem? { items[id] }
        func create(_ item: CalendarItem) throws -> String {
            next += 1
            items["ev\(next)"] = item
            log.append("create \(item.title)")
            return "ev\(next)"
        }
        func update(_ id: String, to item: CalendarItem) throws { items[id] = item; log.append("update \(item.title)") }
        func delete(_ id: String) throws { items[id] = nil; log.append("delete \(id)") }
    }

    @Test("off means nothing; each kind is its own switch")
    func switches() {
        #expect(CalendarPlan.desired(input, settings: CalendarSyncSettings(), now: now, calendar: calendar).isEmpty)
        let only = CalendarPlan.desired(input, settings: CalendarSyncSettings(enabled: true, followUps: false, logs: false, catchUps: true), now: now, calendar: calendar)
        #expect(only.map(\.kind) == [.catchUp, .catchUp])
        let everything = CalendarPlan.desired(input, settings: all, now: now, calendar: calendar)
        #expect(everything.map(\.kind) == [.followUp, .log, .catchUp, .catchUp])
    }

    @Test("a follow-up sits on its due day, a log on its day, both half an hour")
    func followUpAndLog() {
        let items = CalendarPlan.desired(input, settings: all, now: now, calendar: calendar)
        let follow = items.first { $0.kind == .followUp }!
        #expect(follow.title == "Ask how the interview went · Priya")
        #expect(follow.start == day(9, 11, hour: 9))
        #expect(follow.end == day(9, 11, hour: 9).addingTimeInterval(1800))
        #expect(follow.notes == "Figma")
        let log = items.first { $0.kind == .log }!
        #expect(log.title == "Call with Priya")
        #expect(log.start == day(8, 20, hour: 18))
        #expect(log.notes == "Long call about the interview.")
        var done = input
        done.reminders = [.init(id: reminder, title: "x", due: now, done: true, friendName: nil, note: "")]
        #expect(CalendarPlan.desired(done, settings: all, now: now, calendar: calendar).contains { $0.kind == .followUp } == false)
    }

    @Test("a catch-up is the day the cadence runs out, from the last contact or from being added, never before today or a snooze")
    func catchUpDay() {
        let items = CalendarPlan.desired(input, settings: all, now: now, calendar: calendar)
        let priyas = items.first { $0.kind == .catchUp && $0.id == priya }!
        #expect(ymd(priyas.start) == DateComponents(year: 2026, month: 9, day: 19))
        #expect(priyas.allDay)
        #expect(priyas.title == "Reach out to Priya")
        #expect(priyas.notes == "Every 30 days · last talked Aug 20")
        let sams = items.first { $0.kind == .catchUp && $0.id == sam }!
        #expect(ymd(sams.start) == DateComponents(year: 2026, month: 9, day: 8))
        #expect(sams.notes == "Every 7 days · not talked yet")

        let overdue = CalendarPlanInput.FriendLine(id: priya, name: "P", lastContact: day(6, 1), createdAt: day(1, 1), cadenceDays: 30, snoozedUntil: nil, archived: false)
        #expect(CalendarPlan.nextCatchUp(overdue, now: now, calendar: calendar).map(ymd) == DateComponents(year: 2026, month: 9, day: 5))
        let snoozed = CalendarPlanInput.FriendLine(id: priya, name: "P", lastContact: day(8, 20), createdAt: day(1, 1), cadenceDays: 30, snoozedUntil: day(10, 1), archived: false)
        #expect(CalendarPlan.nextCatchUp(snoozed, now: now, calendar: calendar).map(ymd) == DateComponents(year: 2026, month: 10, day: 1))
        let never = CalendarPlanInput.FriendLine(id: priya, name: "P", lastContact: day(8, 20), createdAt: day(1, 1), cadenceDays: nil, snoozedUntil: nil, archived: false)
        #expect(CalendarPlan.nextCatchUp(never, now: now, calendar: calendar) == nil)
        let archived = CalendarPlanInput.FriendLine(id: priya, name: "P", lastContact: day(8, 20), createdAt: day(1, 1), cadenceDays: 30, snoozedUntil: nil, archived: true)
        var gone = input
        gone.friends = [archived]
        #expect(CalendarPlan.desired(gone, settings: all, now: now, calendar: calendar).contains { $0.kind == .catchUp } == false)
    }

    @Test("logging a call moves the catch-up out by the cadence")
    func loggingMovesTheNudge() {
        let before = CalendarPlan.desired(input, settings: all, now: now, calendar: calendar).first { $0.kind == .catchUp && $0.id == priya }!
        #expect(ymd(before.start) == DateComponents(year: 2026, month: 9, day: 19))
        var logged = input
        logged.friends[0] = .init(id: priya, name: "Priya", lastContact: day(9, 5, hour: 14), createdAt: day(1, 1), cadenceDays: 30, snoozedUntil: nil, archived: false)
        let after = CalendarPlan.desired(logged, settings: all, now: now, calendar: calendar).first { $0.kind == .catchUp && $0.id == priya }!
        #expect(ymd(after.start) == DateComponents(year: 2026, month: 10, day: 5))
        #expect(after.key == before.key)
        // Through the store, that is one update of the same event, not a new one.
        let store = Store()
        let first = CalendarSyncer.sync(desired: [before], mapping: CalendarMapping(), store: store, calendar: calendar)
        let second = CalendarSyncer.sync(desired: [after], mapping: first.mapping, store: store, calendar: calendar)
        #expect(store.log == ["create Reach out to Priya", "update Reach out to Priya"])
        #expect(second.mapping.events == first.mapping.events)
        #expect(store.items.count == 1)
    }

    @Test("reconcile creates, updates, removes, and re-creates what was deleted by hand")
    func reconcile() {
        let store = Store()
        let items = CalendarPlan.desired(input, settings: all, now: now, calendar: calendar)
        let first = CalendarSyncer.sync(desired: items, mapping: CalendarMapping(), store: store, calendar: calendar)
        #expect(first.mapping.events.count == 4)
        #expect(first.changed == 4)
        #expect(first.errors.isEmpty)

        let again = CalendarSyncer.sync(desired: items, mapping: first.mapping, store: store, calendar: calendar)
        #expect(again.changed == 0)
        #expect(again.mapping == first.mapping)

        // Removed on the calendar: Tend still wants it, so it comes back under a new identifier.
        let followKey = items.first { $0.kind == .followUp }!.key
        try? store.delete(first.mapping.events[followKey]!)
        let restored = CalendarSyncer.sync(desired: items, mapping: first.mapping, store: store, calendar: calendar)
        #expect(restored.mapping.events[followKey] != first.mapping.events[followKey])
        #expect(store.items.count == 4)

        // Logs switched off: theirs go, the rest stay.
        let noLogs = CalendarPlan.desired(input, settings: CalendarSyncSettings(enabled: true, followUps: true, logs: false, catchUps: true), now: now, calendar: calendar)
        let trimmed = CalendarSyncer.sync(desired: noLogs, mapping: restored.mapping, store: store, calendar: calendar)
        #expect(trimmed.mapping.events.count == 3)
        #expect(store.items.count == 3)
        #expect(store.items.values.contains { $0.kind == .log } == false)

        // Everything off: nothing desired, everything removed.
        let none = CalendarSyncer.sync(desired: [], mapping: trimmed.mapping, store: store, calendar: calendar)
        #expect(none.mapping.events.isEmpty)
        #expect(store.items.isEmpty)
    }

    @Test("an all-day item is its day, whatever the calendar says the day ends")
    func allDaySameness() {
        let a = CalendarItem(kind: .catchUp, id: priya, title: "Reach out to Priya", start: day(9, 19), end: day(9, 20), allDay: true, notes: "n")
        let b = CalendarItem(kind: .catchUp, id: priya, title: "Reach out to Priya", start: day(9, 19, hour: 0), end: day(9, 19, hour: 23), allDay: true, notes: "n")
        #expect(a.sameAs(b, calendar: calendar))
        let c = CalendarItem(kind: .followUp, id: reminder, title: "t", start: day(9, 11, hour: 9), end: day(9, 11, hour: 9).addingTimeInterval(1800), allDay: false, notes: "")
        let d = CalendarItem(kind: .followUp, id: reminder, title: "t", start: day(9, 11, hour: 10), end: day(9, 11, hour: 10).addingTimeInterval(1800), allDay: false, notes: "")
        #expect(!c.sameAs(d, calendar: calendar))
    }
}
