// A Debug-only way to make CloudKit create the record types: write one
// row of every model, wait for the export, delete them, wait again. The
// schema is created in the Development environment the first time a
// development-signed build saves, and nothing else in the app can do
// that on demand. Asked for with the launch argument `-schemaProbe 1`,
// or the environment variable TEND_SCHEMA_PROBE=1, which is how a test
// host launched by xcodebuild on this Mac asks (Tests/SchemaProbeTests).

#if DEBUG
import CloudKit
import Foundation
import os
import SwiftData

enum SchemaProbe {
    static let logger = Logger(subsystem: "com.kevinzhang.tend", category: "schema-probe")

    enum Outcome: Equatable {
        case notAsked, running, exported, failed(String)
    }

    /// Where the probe got to, for the test that keeps the host alive.
    @MainActor private(set) static var outcome = Outcome.notAsked
    @MainActor private(set) static var log: [String] = []

    static var asked: Bool {
        UserDefaults.standard.bool(forKey: "schemaProbe") || ProcessInfo.processInfo.environment["TEND_SCHEMA_PROBE"] == "1"
    }

    @MainActor
    static func runIfAsked(context: ModelContext) {
        guard asked, outcome == .notAsked else { return }
        outcome = .running
        Task { await run(context: context) }
    }

    @MainActor
    private static func note(_ line: String) {
        log.append(line)
        logger.notice("probe: \(line, privacy: .public)")
    }

    @MainActor
    private static func fail(_ line: String) {
        log.append(line)
        logger.error("probe: \(line, privacy: .public)")
        outcome = .failed(line)
    }

    @MainActor
    private static func run(context: ModelContext) async {
        note("store mode \(String(describing: Store.mode))")
        let account = try? await CKContainer(identifier: Store.cloudContainer).accountStatus()
        note("iCloud account status \(account.map { String(describing: $0) } ?? "unknown")")
        guard Store.mode == .cloud else {
            fail("the store is not CloudKit-backed; nothing to materialise")
            return
        }

        let started = Date()
        let group = FriendGroup(name: "Schema probe", cadenceDays: 7, order: 999)
        let friend = Friend(displayName: "Schema Probe")
        friend.groups = [group]
        friend.tags = ["probe"]
        let entry = Entry(kind: .note, date: started, text: "Schema probe entry")
        entry.friends = [friend]
        let fact = Fact(label: "Probe", value: "yes")
        fact.friend = friend
        fact.source = entry
        let reminder = Reminder(title: "Schema probe reminder", due: started.addingTimeInterval(86_400), kind: .custom)
        reminder.friend = friend
        reminder.source = entry
        let date = ImportantDate(label: "Probe day", month: 1, day: 1)
        date.friend = friend
        let method = ContactMethod(kind: .email, value: "probe@example.invalid")
        method.friend = friend
        for object in [group, friend, entry, fact, reminder, date, method] as [any PersistentModel] { context.insert(object) }
        do { try context.save() } catch {
            fail("save failed: \(error.localizedDescription)")
            return
        }
        note("wrote one row of every model; waiting for the export")

        let exportedOK = await exported(after: started)
        if exportedOK { note("export succeeded — the Development schema now has every record type") }

        // The rows go whatever happened: they were never data.
        let cleanup = Date()
        for object in [method, date, reminder, fact, entry, friend, group] as [any PersistentModel] { context.delete(object) }
        try? context.save()
        guard exportedOK else {
            fail("no successful export within the wait — \(SyncMonitor.shared.lastError ?? "no error reported")")
            return
        }
        if await exported(after: cleanup) {
            note("cleanup exported — done")
        } else {
            note("cleanup saved locally but its export did not confirm — \(SyncMonitor.shared.lastError ?? "no error reported")")
        }
        outcome = .exported
    }

    /// A CloudKit export event that ended after `since`, within a minute
    /// and a half; the monitor records them as they land.
    @MainActor
    private static func exported(after since: Date, patience: TimeInterval = 90) async -> Bool {
        let deadline = Date().addingTimeInterval(patience)
        while Date() < deadline {
            if let ok = SyncMonitor.shared.lastSuccess, ok > since { return true }
            if let error = SyncMonitor.shared.lastError, !log.contains("sync error so far — \(error)") { note("sync error so far — \(error)") }
            try? await Task.sleep(for: .seconds(2))
        }
        return false
    }
}
#endif
