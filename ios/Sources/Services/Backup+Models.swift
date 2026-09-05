// Export and import: the SwiftData models to and from the durable records
// in Logic/Backup.swift, plus the zip that carries them with the audio.

import Foundation
import SwiftData

enum Exporter {
    @MainActor
    static func snapshot(context: ModelContext, now: Date = Date()) throws -> Backup {
        let friends = try context.fetch(FetchDescriptor<Friend>(sortBy: [SortDescriptor(\.displayName)]))
        let entries = try context.fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.date)]))
        return Backup(
            exportedAt: now,
            friends: friends.map(record),
            entries: entries.map { e in
                Backup.EntryRecord(
                    id: e.id, date: e.date, kind: e.kindRaw, text: e.text, transcript: e.transcript,
                    audioFile: e.audioFile, durationSeconds: e.durationSeconds, createdAt: e.createdAt,
                    friendIds: (e.friends ?? []).map(\.id))
            })
    }

    private static func record(_ f: Friend) -> Backup.FriendRecord {
        Backup.FriendRecord(
            id: f.id, displayName: f.displayName, givenName: f.givenName, familyName: f.familyName,
            nickname: f.nickname, photoBase64: f.photo?.base64EncodedString(),
            contactIdentifier: f.contactIdentifier, circle: f.circleRaw, cadenceDays: f.cadenceDays,
            snoozedUntil: f.snoozedUntil, tags: f.tags, location: f.location,
            timeZoneIdentifier: f.timeZoneIdentifier, howWeMet: f.howWeMet, about: f.about,
            archived: f.archived, createdAt: f.createdAt, updatedAt: f.updatedAt,
            methods: (f.methods ?? []).map {
                Backup.MethodRecord(id: $0.id, kind: $0.kindRaw, value: $0.value, label: $0.label, preferred: $0.preferred)
            },
            facts: (f.facts ?? []).map {
                Backup.FactRecord(id: $0.id, label: $0.label, value: $0.value, updatedAt: $0.updatedAt, sourceEntryId: $0.source?.id)
            },
            reminders: (f.reminders ?? []).map {
                Backup.ReminderRecord(id: $0.id, title: $0.title, due: $0.due, note: $0.note, done: $0.done,
                                      doneAt: $0.doneAt, kind: $0.kindRaw, createdAt: $0.createdAt, sourceEntryId: $0.source?.id)
            },
            dates: (f.dates ?? []).map {
                Backup.DateRecord(id: $0.id, label: $0.label, month: $0.month, day: $0.day, year: $0.year, remind: $0.remind)
            })
    }

    /// Writes the export folder and zips it. The zip comes from
    /// NSFileCoordinator's upload path, which is the one zip the platform
    /// will make without a library.
    @MainActor
    static func exportZip(context: ModelContext, now: Date = Date()) throws -> URL {
        let backup = try snapshot(context: context, now: now)
        let stamp = now.formatted(.iso8601.year().month().day())
        let tmp = FileManager.default.temporaryDirectory
        let root = tmp.appendingPathComponent("Tend-\(stamp)", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Backup.encode(backup).write(to: root.appendingPathComponent("backup.json"))
        try backup.friendsCSV(now: now).write(to: root.appendingPathComponent("friends.csv"), atomically: true, encoding: .utf8)
        try backup.entriesCSV().write(to: root.appendingPathComponent("entries.csv"), atomically: true, encoding: .utf8)
        let audio = root.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        for file in backup.entries.compactMap(\.audioFile) where AudioStore.exists(file) {
            try FileManager.default.copyItem(at: AudioStore.url(for: file), to: audio.appendingPathComponent(file))
        }

        let zip = tmp.appendingPathComponent("Tend-\(stamp).zip")
        try? FileManager.default.removeItem(at: zip)
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: root, options: .forUploading, error: &coordinatorError) { zipped in
            do { try FileManager.default.copyItem(at: zipped, to: zip) } catch { copyError = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
        let size = (try? FileManager.default.attributesOfItem(atPath: zip.path)[.size] as? Int) ?? 0
        guard size > 0 else { throw ExportError.emptyArchive }
        return zip
    }
}

enum ExportError: Error, LocalizedError {
    case emptyArchive
    var errorDescription: String? { "The export produced an empty archive." }
}

enum Importer {
    struct Summary: Equatable {
        var friendsCreated = 0
        var friendsUpdated = 0
        var entriesCreated = 0
        var entriesUpdated = 0
        var audioRestored = 0

        var description: String {
            "\(friendsCreated + friendsUpdated) friends (\(friendsCreated) new) · \(entriesCreated + entriesUpdated) entries (\(entriesCreated) new)"
                + (audioRestored > 0 ? " · \(audioRestored) recordings" : "")
        }
    }

    /// Reads a backup.json or the folder holding one, and merges it in by
    /// id: rows that exist are updated, rows that don't are created,
    /// nothing is deleted. Audio beside the JSON is restored when missing.
    @MainActor
    static func importBackup(from picked: URL, into context: ModelContext) throws -> Summary {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }

        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: picked.path, isDirectory: &isDirectory)
        let json = isDirectory.boolValue ? picked.appendingPathComponent("backup.json") : picked
        let audioDir = json.deletingLastPathComponent().appendingPathComponent("audio", isDirectory: true)
        guard FileManager.default.fileExists(atPath: json.path) else { throw BackupError.notABackup }
        let backup = try Backup.decode(try Data(contentsOf: json))
        return try merge(backup, audioDir: audioDir, into: context)
    }

    @MainActor
    static func merge(_ backup: Backup, audioDir: URL?, into context: ModelContext) throws -> Summary {
        var summary = Summary()
        var friendsById = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Friend>()).map { ($0.id, $0) })
        var entriesById = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Entry>()).map { ($0.id, $0) })

        // Entries first: facts and reminders point at them.
        for record in backup.entries {
            let entry: Entry
            if let existing = entriesById[record.id] {
                entry = existing
                summary.entriesUpdated += 1
            } else {
                entry = Entry()
                entry.id = record.id
                context.insert(entry)
                entriesById[record.id] = entry
                summary.entriesCreated += 1
            }
            entry.date = record.date
            entry.kindRaw = record.kind
            entry.text = record.text
            entry.transcript = record.transcript
            entry.audioFile = record.audioFile
            entry.durationSeconds = record.durationSeconds
            entry.createdAt = record.createdAt
            if let file = record.audioFile, let audioDir, !AudioStore.exists(file) {
                let source = audioDir.appendingPathComponent(file)
                if FileManager.default.fileExists(atPath: source.path),
                   (try? FileManager.default.copyItem(at: source, to: AudioStore.url(for: file))) != nil {
                    summary.audioRestored += 1
                }
            }
        }

        for record in backup.friends {
            let friend: Friend
            if let existing = friendsById[record.id] {
                friend = existing
                summary.friendsUpdated += 1
            } else {
                friend = Friend()
                friend.id = record.id
                context.insert(friend)
                friendsById[record.id] = friend
                summary.friendsCreated += 1
            }
            friend.displayName = record.displayName
            friend.givenName = record.givenName
            friend.familyName = record.familyName
            friend.nickname = record.nickname
            friend.photo = record.photoBase64.flatMap { Data(base64Encoded: $0) }
            friend.contactIdentifier = record.contactIdentifier
            friend.circleRaw = record.circle
            friend.cadenceDays = record.cadenceDays
            friend.snoozedUntil = record.snoozedUntil
            friend.tags = record.tags
            friend.location = record.location
            friend.timeZoneIdentifier = record.timeZoneIdentifier
            friend.howWeMet = record.howWeMet
            friend.about = record.about
            friend.archived = record.archived
            friend.createdAt = record.createdAt
            friend.updatedAt = record.updatedAt

            var methods = Dictionary(uniqueKeysWithValues: (friend.methods ?? []).map { ($0.id, $0) })
            for m in record.methods {
                let method = methods[m.id] ?? {
                    let new = ContactMethod(kind: ContactKind(rawValue: m.kind) ?? .url, value: m.value)
                    new.id = m.id
                    new.friend = friend
                    context.insert(new)
                    methods[m.id] = new
                    return new
                }()
                method.kindRaw = m.kind
                method.value = m.value
                method.label = m.label
                method.preferred = m.preferred
            }
            var facts = Dictionary(uniqueKeysWithValues: (friend.facts ?? []).map { ($0.id, $0) })
            for f in record.facts {
                let fact = facts[f.id] ?? {
                    let new = Fact(label: f.label, value: f.value)
                    new.id = f.id
                    new.friend = friend
                    context.insert(new)
                    facts[f.id] = new
                    return new
                }()
                fact.label = f.label
                fact.value = f.value
                fact.updatedAt = f.updatedAt
                fact.source = f.sourceEntryId.flatMap { entriesById[$0] }
            }
            var reminders = Dictionary(uniqueKeysWithValues: (friend.reminders ?? []).map { ($0.id, $0) })
            for r in record.reminders {
                let reminder = reminders[r.id] ?? {
                    let new = Reminder(title: r.title, due: r.due)
                    new.id = r.id
                    new.friend = friend
                    context.insert(new)
                    reminders[r.id] = new
                    return new
                }()
                reminder.title = r.title
                reminder.due = r.due
                reminder.note = r.note
                reminder.done = r.done
                reminder.doneAt = r.doneAt
                reminder.kindRaw = r.kind
                reminder.createdAt = r.createdAt
                reminder.source = r.sourceEntryId.flatMap { entriesById[$0] }
            }
            var dates = Dictionary(uniqueKeysWithValues: (friend.dates ?? []).map { ($0.id, $0) })
            for d in record.dates {
                let date = dates[d.id] ?? {
                    let new = ImportantDate(label: d.label, month: d.month, day: d.day)
                    new.id = d.id
                    new.friend = friend
                    context.insert(new)
                    dates[d.id] = new
                    return new
                }()
                date.label = d.label
                date.month = d.month
                date.day = d.day
                date.year = d.year
                date.remind = d.remind
            }
        }

        // Links last, once both sides exist.
        for record in backup.entries {
            guard let entry = entriesById[record.id] else { continue }
            let linked = record.friendIds.compactMap { friendsById[$0] }
            let current = Set((entry.friends ?? []).map(\.id))
            for friend in linked where !current.contains(friend.id) {
                if entry.friends == nil { entry.friends = [] }
                entry.friends?.append(friend)
            }
        }
        try context.save()
        return summary
    }
}
