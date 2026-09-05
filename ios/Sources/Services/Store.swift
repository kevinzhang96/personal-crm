// The one SwiftData container. Everything the app persists is in this
// schema, and nothing else opens the store.

import Foundation
import SwiftData

enum Store {
    static let schema = Schema([
        Friend.self, FriendGroup.self, ContactMethod.self, Entry.self, Fact.self, Reminder.self, ImportantDate.self,
    ])

    static func container(inMemory: Bool = false) throws -> ModelContainer {
        // The default store lives in Application Support, which a fresh
        // container does not yet have; SwiftData recovers, loudly.
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
