// What Tend puts on the reader's calendar, decided from plain values:
// each open follow-up on its due day, each log on its day, and each
// friend's next catch-up on the day their cadence runs out — recomputed
// from the last contact every time, so logging a call moves the nudge.
// Tend is the source of truth and the calendar a one-way mirror:
// `reconcile` says what to create, change or remove given what the
// calendar already holds, and `CalendarSyncer` does it through whatever
// store the shell supplies (EventKit in the app, a dictionary in tests).

import Foundation

struct CalendarSyncSettings: Equatable {
    var enabled = false
    var followUps = true
    var logs = true
    var catchUps = true
}

/// One thing on the calendar. Dates are whole seconds, which is what a
/// calendar keeps, so a read-back compares equal.
struct CalendarItem: Equatable, Hashable {
    enum Kind: String, CaseIterable {
        case followUp, log, catchUp
    }

    let kind: Kind
    /// The Tend object it mirrors: a reminder, an entry, or — for a
    /// catch-up — the friend. Stable across reconciles.
    let id: UUID
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let notes: String

    init(kind: Kind, id: UUID, title: String, start: Date, end: Date, allDay: Bool, notes: String) {
        self.kind = kind
        self.id = id
        self.title = title
        self.start = Self.seconds(start)
        self.end = Self.seconds(end)
        self.allDay = allDay
        self.notes = notes
    }

    var key: String { "\(kind.rawValue):\(id.uuidString)" }

    /// Nothing the reader would notice has changed. An all-day item is
    /// its day; the calendar's own idea of where the day ends varies.
    func sameAs(_ other: CalendarItem, calendar: Calendar) -> Bool {
        guard title == other.title, notes == other.notes, allDay == other.allDay else { return false }
        if allDay { return calendar.isDate(start, inSameDayAs: other.start) }
        return start == other.start && end == other.end
    }

    private static func seconds(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.down))
    }
}

/// The store, as plain values.
struct CalendarPlanInput: Equatable {
    struct FriendLine: Equatable {
        let id: UUID
        let name: String
        let lastContact: Date?
        let createdAt: Date
        let cadenceDays: Int?
        let snoozedUntil: Date?
        let archived: Bool
    }

    struct ReminderLine: Equatable {
        let id: UUID
        let title: String
        let due: Date
        let done: Bool
        let friendName: String?
        let note: String
    }

    struct EntryLine: Equatable {
        let id: UUID
        let date: Date
        let kind: String
        let friendNames: [String]
        let text: String
    }

    var friends: [FriendLine] = []
    var reminders: [ReminderLine] = []
    var entries: [EntryLine] = []
}

enum CalendarPlan {
    /// A follow-up or a log takes half an hour on the calendar.
    static let minutes = 30
    static let calendarTitle = "Tend"

    /// Everything Tend wants on the calendar right now.
    static func desired(_ input: CalendarPlanInput, settings: CalendarSyncSettings, now: Date, calendar: Calendar = .current) -> [CalendarItem] {
        guard settings.enabled else { return [] }
        var out: [CalendarItem] = []
        let length = TimeInterval(minutes * 60)
        if settings.followUps {
            for r in input.reminders where !r.done {
                let title = r.friendName.map { "\(r.title) · \($0)" } ?? r.title
                out.append(CalendarItem(kind: .followUp, id: r.id, title: title, start: r.due, end: r.due.addingTimeInterval(length), allDay: false, notes: r.note))
            }
        }
        if settings.logs {
            for e in input.entries {
                let who = e.friendNames.joined(separator: ", ")
                let title = who.isEmpty ? e.kind : (e.kind == "Note" ? "Note about \(who)" : "\(e.kind) with \(who)")
                out.append(CalendarItem(kind: .log, id: e.id, title: title, start: e.date, end: e.date.addingTimeInterval(length), allDay: false,
                                        notes: String(e.text.prefix(300))))
            }
        }
        if settings.catchUps {
            for f in input.friends where !f.archived {
                guard let day = nextCatchUp(f, now: now, calendar: calendar), let cadence = f.cadenceDays else { continue }
                let last = f.lastContact.map { "last talked " + $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "not talked yet"
                out.append(CalendarItem(kind: .catchUp, id: f.id, title: "Reach out to \(f.name)", start: day,
                                        end: calendar.date(byAdding: .day, value: 1, to: day) ?? day, allDay: true,
                                        notes: "Every \(cadence) days · \(last)"))
            }
        }
        return out
    }

    /// The day a friend's cadence runs out — the same clock as Cadence:
    /// from the last contact, or from when they were added — never
    /// before a snooze ends, and never earlier than today, because a
    /// nudge in the past is not a nudge. Nil for a friend never nudged.
    static func nextCatchUp(_ f: CalendarPlanInput.FriendLine, now: Date, calendar: Calendar) -> Date? {
        guard let cadence = f.cadenceDays, cadence > 0 else { return nil }
        let today = calendar.startOfDay(for: now)
        let anchor = calendar.startOfDay(for: f.lastContact ?? f.createdAt)
        var day = calendar.date(byAdding: .day, value: cadence, to: anchor) ?? today
        if let snoozed = f.snoozedUntil { day = max(day, calendar.startOfDay(for: snoozed)) }
        return max(day, today)
    }

    /// What to do to the calendar so it matches `desired`, given what the
    /// mapping says was put there and what the store says is still there.
    static func reconcile(desired: [CalendarItem], mapping: CalendarMapping, existing: (String) -> CalendarItem?,
                          calendar: Calendar = .current) -> CalendarReconciliation {
        var r = CalendarReconciliation()
        var wanted: Set<String> = []
        for item in desired {
            wanted.insert(item.key)
            if let id = mapping.events[item.key] {
                if let there = existing(id) {
                    if !there.sameAs(item, calendar: calendar) { r.update.append(.init(id: id, item: item)) }
                } else {
                    // Removed by hand on the calendar: Tend still wants it.
                    r.forget.append(item.key)
                    r.create.append(item)
                }
            } else {
                r.create.append(item)
            }
        }
        for (key, id) in mapping.events where !wanted.contains(key) {
            if existing(id) != nil { r.delete.append(id) }
            r.forget.append(key)
        }
        return r
    }
}

/// What the calendar was given, kept on this device only: a calendar's
/// and its events' identifiers belong to one device and one account.
struct CalendarMapping: Codable, Equatable {
    var calendar: String?
    /// Item key → the calendar's identifier for it.
    var events: [String: String] = [:]
}

struct CalendarReconciliation: Equatable {
    struct Update: Equatable {
        let id: String
        let item: CalendarItem
    }

    var create: [CalendarItem] = []
    var update: [Update] = []
    var delete: [String] = []
    var forget: [String] = []

    var isEmpty: Bool { create.isEmpty && update.isEmpty && delete.isEmpty && forget.isEmpty }
}

/// The calendar as somewhere items live under identifiers.
protocol CalendarStore {
    /// The item under an identifier, or nil once it is gone.
    func item(_ id: String) throws -> CalendarItem?
    func create(_ item: CalendarItem) throws -> String
    func update(_ id: String, to item: CalendarItem) throws
    func delete(_ id: String) throws
}

enum CalendarSyncer {
    struct Result: Equatable {
        var mapping: CalendarMapping
        var errors: [String] = []
        var changed = 0
    }

    /// Desired → reconcile → store, and the mapping as it stands after.
    /// One item failing does not stop the rest; its error is reported.
    static func sync(desired: [CalendarItem], mapping: CalendarMapping, store: CalendarStore, calendar: Calendar = .current) -> Result {
        let plan = CalendarPlan.reconcile(desired: desired, mapping: mapping, existing: { try? store.item($0) }, calendar: calendar)
        var result = Result(mapping: mapping)
        for key in plan.forget { result.mapping.events[key] = nil }
        for id in plan.delete {
            do { try store.delete(id); result.changed += 1 } catch { result.errors.append("remove: \(error.localizedDescription)") }
        }
        for u in plan.update {
            do { try store.update(u.id, to: u.item); result.changed += 1 } catch { result.errors.append("\(u.item.title): \(error.localizedDescription)") }
        }
        for item in plan.create {
            do {
                result.mapping.events[item.key] = try store.create(item)
                result.changed += 1
            } catch {
                result.errors.append("\(item.title): \(error.localizedDescription)")
            }
        }
        return result
    }
}
