// The calendar, through EventKit: a "Tend" calendar of its own, made on
// first use, so everything the app puts there can be removed together;
// the mapping from Tend's objects to the calendar's identifiers kept in
// a file on this device, because those identifiers are this device's
// and this account's — never in the store, never in iCloud. Off by
// default; the first switch-on asks for access, right then.
//
// Full access rather than write-only: write-only can add an event but
// never read it back, so it could not change or remove what it added,
// nor make and later remove a calendar of its own.

import EventKit
import Foundation
import Observation
import SwiftData
import UIKit

@MainActor
@Observable
final class CalendarSync {
    static let shared = CalendarSync()

    static let enabledKey = "calendar.enabled"
    static let followUpsKey = "calendar.followUps"
    static let logsKey = "calendar.logs"
    static let catchUpsKey = "calendar.catchUps"

    private(set) var lastSync: Date?
    private(set) var lastError: String?
    private(set) var count = 0
    private var store: EventKitStore?
    private var running = false

    static func settings(_ defaults: UserDefaults = .standard) -> CalendarSyncSettings {
        var s = CalendarSyncSettings()
        s.enabled = defaults.bool(forKey: enabledKey)
        if defaults.object(forKey: followUpsKey) != nil { s.followUps = defaults.bool(forKey: followUpsKey) }
        if defaults.object(forKey: logsKey) != nil { s.logs = defaults.bool(forKey: logsKey) }
        if defaults.object(forKey: catchUpsKey) != nil { s.catchUps = defaults.bool(forKey: catchUpsKey) }
        return s
    }

    var authorization: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    var authorized: Bool { authorization == .fullAccess }

    /// Asked the moment sync is switched on, never at launch.
    func requestAccess() async -> Bool {
        if authorized { return true }
        let granted = (try? await EventKitStore.shared.store.requestFullAccessToEvents()) ?? false
        return granted && authorized
    }

    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    /// The calendar made to match the store. Cheap when nothing changed;
    /// the whole diff is a few hundred comparisons.
    func reconcile(context: ModelContext, now: Date = Date()) async {
        let settings = Self.settings()
        guard settings.enabled, authorized, !running else { return }
        running = true
        defer { running = false }
        var mapping = CalendarMapping.load()
        let store = EventKitStore.shared
        do {
            mapping.calendar = try store.tendCalendar(id: mapping.calendar).calendarIdentifier
        } catch {
            lastError = "Couldn't make the Tend calendar: \(error.localizedDescription)"
            return
        }
        let desired = CalendarPlan.desired(Self.input(context: context), settings: settings, now: now)
        let result = CalendarSyncer.sync(desired: desired, mapping: mapping, store: store)
        result.mapping.save()
        count = result.mapping.events.count
        lastSync = now
        lastError = result.errors.first
    }

    /// Sync off: the Tend calendar goes, and with it everything on it.
    func turnOff() {
        var mapping = CalendarMapping.load()
        if let id = mapping.calendar { try? EventKitStore.shared.removeCalendar(id: id) }
        mapping = CalendarMapping()
        mapping.save()
        count = 0
        lastSync = nil
        lastError = nil
    }

    static func input(context: ModelContext) -> CalendarPlanInput {
        let friends = (try? context.fetch(FetchDescriptor<Friend>())) ?? []
        let reminders = (try? context.fetch(FetchDescriptor<Reminder>(predicate: #Predicate { !$0.done }))) ?? []
        let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        return CalendarPlanInput(
            friends: friends.map {
                .init(id: $0.id, name: $0.displayName, lastContact: $0.lastContact, createdAt: $0.createdAt,
                      cadenceDays: $0.effectiveCadenceDays, snoozedUntil: $0.snoozedUntil, archived: $0.archived)
            },
            reminders: reminders.map {
                .init(id: $0.id, title: $0.title, due: $0.due, done: $0.done, friendName: $0.friend?.displayName, note: $0.note)
            },
            entries: entries.map {
                .init(id: $0.id, date: $0.date, kind: $0.kind.label, friendNames: ($0.friends ?? []).map(\.displayName).sorted(), text: $0.body)
            })
    }
}

extension CalendarMapping {
    /// Device-local, beside the store but not in it.
    static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("calendar-sync.json")
    }

    static func load() -> CalendarMapping {
        guard let data = try? Data(contentsOf: file), let m = try? JSONDecoder().decode(CalendarMapping.self, from: data) else { return CalendarMapping() }
        return m
    }

    func save() {
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: Self.file, options: .atomic)
    }
}

/// EventKit behind the store protocol. One event store for the app: it
/// is costly to make and remembers what it has loaded.
final class EventKitStore: CalendarStore {
    static let shared = EventKitStore()
    let store = EKEventStore()

    struct Missing: LocalizedError {
        var errorDescription: String? { "the event is no longer on the calendar" }
    }

    /// The Tend calendar by its remembered identifier, or a new one in
    /// the iCloud source when there is one, so it follows the reader's
    /// account, else wherever new events go by default.
    func tendCalendar(id: String?) throws -> EKCalendar {
        if let id, let existing = store.calendar(withIdentifier: id) { return existing }
        if let found = store.calendars(for: .event).first(where: { $0.title == CalendarPlan.calendarTitle && $0.allowsContentModifications }) {
            return found
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = CalendarPlan.calendarTitle
        calendar.cgColor = UIColor(Theme.accent).cgColor
        guard let source = store.sources.first(where: { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") })
                ?? store.defaultCalendarForNewEvents?.source
                ?? store.sources.first(where: { $0.sourceType == .local })
        else { throw Missing() }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    func removeCalendar(id: String) throws {
        guard let calendar = store.calendar(withIdentifier: id) else { return }
        try store.removeCalendar(calendar, commit: true)
    }

    func item(_ id: String) throws -> CalendarItem? {
        guard let event = store.event(withIdentifier: id) else { return nil }
        // The kind and id are Tend's; the read-back only needs what is compared.
        return CalendarItem(kind: .log, id: UUID(), title: event.title ?? "", start: event.startDate, end: event.endDate,
                            allDay: event.isAllDay, notes: event.notes ?? "")
    }

    func create(_ item: CalendarItem) throws -> String {
        let event = EKEvent(eventStore: store)
        event.calendar = try tendCalendar(id: CalendarMapping.load().calendar)
        fill(event, from: item)
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier ?? ""
    }

    func update(_ id: String, to item: CalendarItem) throws {
        guard let event = store.event(withIdentifier: id) else { throw Missing() }
        fill(event, from: item)
        try store.save(event, span: .thisEvent, commit: true)
    }

    func delete(_ id: String) throws {
        guard let event = store.event(withIdentifier: id) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    private func fill(_ event: EKEvent, from item: CalendarItem) {
        event.title = item.title
        event.startDate = item.start
        event.endDate = item.end
        event.isAllDay = item.allDay
        event.notes = item.notes.isEmpty ? nil : item.notes
    }
}
