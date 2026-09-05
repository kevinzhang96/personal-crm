// The durable format round-trips, refuses the future, and renders CSV
// that a spreadsheet will open.

import Foundation
import Testing
@testable import Tend

struct BackupTests {
    let calendar = Calendar(identifier: .gregorian)
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 12))! }

    func sample() -> Backup {
        let ana = UUID(), ben = UUID(), entry = UUID()
        return Backup(
            exportedAt: now,
            friends: [
                Backup.FriendRecord(id: ana, displayName: "Ana, \"the\" Explorer", circle: "close", tags: ["college", "hiking"],
                                    createdAt: now, updatedAt: now,
                                    methods: [Backup.MethodRecord(id: UUID(), kind: "phone", value: "+15550102030")],
                                    facts: [Backup.FactRecord(id: UUID(), label: "Partner", value: "Marco", updatedAt: now, sourceEntryId: entry)],
                                    reminders: [Backup.ReminderRecord(id: UUID(), title: "Ask about Lisbon", due: now, kind: "followUp", createdAt: now, sourceEntryId: entry)],
                                    dates: [Backup.DateRecord(id: UUID(), label: "Birthday", month: 3, day: 14, year: 1992)]),
                Backup.FriendRecord(id: ben, displayName: "Ben", circle: "inner", createdAt: calendar.date(byAdding: .day, value: -30, to: now)!, updatedAt: now),
            ],
            entries: [
                Backup.EntryRecord(id: entry, date: calendar.date(byAdding: .day, value: -2, to: now)!, kind: "call",
                                   text: "Talked about the\nLisbon trip", createdAt: now, friendIds: [ana]),
                Backup.EntryRecord(id: UUID(), date: calendar.date(byAdding: .day, value: -50, to: now)!, kind: "note",
                                   text: "Likes kettles", createdAt: now, friendIds: [ben]),
            ])
    }

    @Test("encode then decode is the identity")
    func roundTrip() throws {
        let original = sample()
        let data = try Backup.encode(original)
        let decoded = try Backup.decode(data)
        #expect(decoded == original)
        #expect(String(data: data, encoding: .utf8)!.contains("\"version\" : 1"))
    }

    @Test("a backup from a newer app is refused rather than half-read")
    func newer() {
        var future = sample()
        future.version = Backup.currentVersion + 1
        let data = try! Backup.encode(future)
        #expect(throws: BackupError.self) { try Backup.decode(data) }
    }

    @Test("friends.csv derives last contact and status; notes don't count as contact")
    func friendsCSV() {
        let csv = sample().friendsCSV(now: now, calendar: calendar)
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines[0] == "name,circle,cadence_days,last_contact,status,tags,location,birthday,archived")
        #expect(lines[1] == "\"Ana, \"\"the\"\" Explorer\",close,30,2026-09-03,on track,college;hiking,,03-14-1992,")
        // Ben: only a note, 50 days ago; created 30 days ago on a 7-day cadence -> 23 over.
        #expect(lines[2] == "Ben,inner,7,,overdue 23d,,,,")
    }

    @Test("entries.csv quotes newlines and names the friends")
    func entriesCSV() {
        let csv = sample().entriesCSV()
        #expect(csv.contains("2026-09-03,call,\"Ana, \"\"the\"\" Explorer\",\"Talked about the\nLisbon trip\",,"))
        #expect(csv.hasPrefix("date,kind,friends,text,audio_file,duration_seconds\n"))
    }

    @Test("CSV quoting only when needed")
    func quoting() {
        #expect(CSV.quote("plain") == "plain")
        #expect(CSV.quote("a,b") == "\"a,b\"")
        #expect(CSV.quote("say \"hi\"") == "\"say \"\"hi\"\"\"")
    }
}
