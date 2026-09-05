// The durable format. These records are decoded on their own terms —
// never through the SwiftData models — so an export from any version can
// be read by any later one. `version` is bumped with a migration when the
// shape changes; fields are only ever added.

import Foundation

struct Backup: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = Backup.currentVersion
    var exportedAt: Date
    var friends: [FriendRecord]
    var entries: [EntryRecord]

    struct FriendRecord: Codable, Equatable {
        var id: UUID
        var displayName: String
        var givenName: String = ""
        var familyName: String = ""
        var nickname: String = ""
        var photoBase64: String?
        var contactIdentifier: String?
        var circle: String
        var cadenceDays: Int?
        var snoozedUntil: Date?
        var tags: [String] = []
        var location: String = ""
        var timeZoneIdentifier: String?
        var howWeMet: String = ""
        var about: String = ""
        var archived: Bool = false
        var createdAt: Date
        var updatedAt: Date
        var methods: [MethodRecord] = []
        var facts: [FactRecord] = []
        var reminders: [ReminderRecord] = []
        var dates: [DateRecord] = []
    }

    struct MethodRecord: Codable, Equatable {
        var id: UUID
        var kind: String
        var value: String
        var label: String = ""
        var preferred: Bool = false
    }

    struct FactRecord: Codable, Equatable {
        var id: UUID
        var label: String
        var value: String
        var updatedAt: Date
        var sourceEntryId: UUID?
    }

    struct ReminderRecord: Codable, Equatable {
        var id: UUID
        var title: String
        var due: Date
        var note: String = ""
        var done: Bool = false
        var doneAt: Date?
        var kind: String
        var createdAt: Date
        var sourceEntryId: UUID?
    }

    struct DateRecord: Codable, Equatable {
        var id: UUID
        var label: String
        var month: Int
        var day: Int
        var year: Int?
        var remind: Bool = true
    }

    struct EntryRecord: Codable, Equatable {
        var id: UUID
        var date: Date
        var kind: String
        var text: String = ""
        var transcript: String = ""
        var audioFile: String?
        var durationSeconds: Double?
        var createdAt: Date
        var friendIds: [UUID] = []
    }

    // MARK: codec

    static func encode(_ backup: Backup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> Backup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Backup.self, from: data)
        guard backup.version <= currentVersion else {
            throw BackupError.newerVersion(backup.version)
        }
        return backup
    }

    // MARK: CSV

    /// One row per friend, with the derived columns a spreadsheet reader
    /// would otherwise have to compute.
    func friendsCSV(now: Date, calendar: Calendar = .current) -> String {
        let lastContact = Dictionary(grouping: entries.flatMap { e in e.friendIds.map { ($0, e) } }, by: \.0)
            .mapValues { pairs in
                pairs.map(\.1).filter { EntryKind(rawValue: $0.kind)?.countsAsContact ?? false }.map(\.date).max()
            }
        let header = ["name", "circle", "cadence_days", "last_contact", "status", "tags", "location", "birthday", "archived"]
        let rows = friends.map { f -> [String] in
            let last = lastContact[f.id] ?? nil
            let cadence = f.cadenceDays ?? FriendCircle(rawValue: f.circle)?.defaultCadenceDays
            let status = Cadence.status(
                lastContact: last, cadenceDays: cadence, snoozedUntil: f.snoozedUntil,
                createdAt: f.createdAt, now: now, calendar: calendar)
            let birthday = f.dates.first { $0.label.caseInsensitiveCompare(ImportantDate.birthdayLabel) == .orderedSame }
            return [
                f.displayName, f.circle, cadence.map(String.init) ?? "",
                last.map(Self.day) ?? "", Self.statusWord(status),
                f.tags.joined(separator: ";"), f.location,
                birthday.map { d in String(format: "%02d-%02d", d.month, d.day) + (d.year.map { "-\($0)" } ?? "") } ?? "",
                f.archived ? "yes" : "",
            ]
        }
        return CSV.render(header: header, rows: rows)
    }

    func entriesCSV() -> String {
        let names = Dictionary(uniqueKeysWithValues: friends.map { ($0.id, $0.displayName) })
        let header = ["date", "kind", "friends", "text", "audio_file", "duration_seconds"]
        let rows = entries.sorted { $0.date > $1.date }.map { e -> [String] in
            [
                Self.day(e.date), e.kind,
                e.friendIds.compactMap { names[$0] }.joined(separator: "; "),
                e.text.isEmpty ? e.transcript : e.text,
                e.audioFile ?? "", e.durationSeconds.map { String(Int($0)) } ?? "",
            ]
        }
        return CSV.render(header: header, rows: rows)
    }

    private static func day(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }

    private static func statusWord(_ status: ContactStatus) -> String {
        switch status {
        case .never: "no nudges"
        case .snoozed: "snoozed"
        case .onTrack: "on track"
        case .dueSoon: "due soon"
        case .overdue(let d): "overdue \(d)d"
        }
    }
}

enum BackupError: Error, LocalizedError {
    case newerVersion(Int)
    case notABackup

    var errorDescription: String? {
        switch self {
        case .newerVersion(let v): "This backup is version \(v); this app reads up to \(Backup.currentVersion). Update the app."
        case .notABackup: "That file isn't a Tend backup (expected backup.json or a folder containing one)."
        }
    }
}

enum CSV {
    static func render(header: [String], rows: [[String]]) -> String {
        ([header] + rows).map { $0.map(quote).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    /// RFC 4180: quote when the field has a comma, quote, or newline;
    /// double the quotes inside.
    static func quote(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
