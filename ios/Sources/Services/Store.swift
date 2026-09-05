// The one SwiftData container. CloudKit-backed when the build carries the
// entitlement and the system lets it open; otherwise local, and Settings
// says why. The store that existed before sync is imported once into the
// synced one through the backup codec, so nothing depends on CloudKit
// adopting a file it did not create.

import Foundation
import SwiftData

enum Store {
    static let cloudContainer = "iCloud.com.kevinzhang.tend"

    enum Mode: Equatable {
        case cloud
        case local(reason: String)
    }

    /// How this process's store was opened.
    private(set) static var mode: Mode = .local(reason: "not opened")

    static let schema = Schema([
        Friend.self, FriendGroup.self, ContactMethod.self, Entry.self, Fact.self, Reminder.self, ImportantDate.self,
    ])

    static func container(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }
        let support = try supportDirectory()
        let cloudURL = support.appendingPathComponent("cloud.store")
        do {
            let config = ModelConfiguration("cloud", schema: schema, url: cloudURL, cloudKitDatabase: .private(cloudContainer))
            let container = try ModelContainer(for: schema, configurations: [config])
            mode = .cloud
            return container
        } catch {
            // A build without the capability, or a system that refused it:
            // the local store carries on exactly as before.
            mode = .local(reason: Self.plain(error))
            let config = ModelConfiguration("local", schema: schema, url: legacyURL(in: support), cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [config])
        }
    }

    /// Whether data from before sync is still waiting to be carried over.
    static var legacyPending: Bool {
        guard let support = try? supportDirectory() else { return false }
        let legacy = legacyURL(in: support)
        return FileManager.default.fileExists(atPath: legacy.path)
            && !FileManager.default.fileExists(atPath: migratedMarker(for: legacy).path)
    }

    /// Carries the pre-sync store into the synced one, once. The old file
    /// stays, marked, so a failure here is retried next launch and never
    /// costs data.
    @MainActor
    static func migrateLegacy(into container: ModelContainer) {
        guard mode == .cloud, legacyPending, let support = try? supportDirectory() else { return }
        let legacy = legacyURL(in: support)
        do {
            let old = try ModelContainer(
                for: schema, configurations: [ModelConfiguration("legacy", schema: schema, url: legacy, cloudKitDatabase: .none)])
            let backup = try Exporter.snapshot(context: old.mainContext)
            let recordings = Dictionary(uniqueKeysWithValues: try old.mainContext.fetch(FetchDescriptor<Entry>()).compactMap { e -> (UUID, Data)? in
                guard let data = e.audio ?? e.audioFile.flatMap(AudioStore.data) else { return nil }
                return (e.id, data)
            })
            let summary = try Importer.merge(backup, audioDir: AudioStore.directory, into: container.mainContext, audio: recordings)
            try Data("\(Date()) \(summary.description)\n".utf8).write(to: migratedMarker(for: legacy))
        } catch {
            // Next launch tries again; the marker is only written on success.
        }
    }

    private static func supportDirectory() throws -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }

    private static func legacyURL(in support: URL) -> URL { support.appendingPathComponent("default.store") }

    private static func migratedMarker(for legacy: URL) -> URL { legacy.appendingPathExtension("migrated") }

    private static func plain(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("entitlement") { return "this build has no iCloud entitlement" }
        return text
    }
}
