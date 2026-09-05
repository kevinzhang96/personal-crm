// The groups' one invariant: every friend is in one. Seeds the built-in
// circles on first launch, and moves any friend without a group — an
// install from before groups existed, or a deleted group's stragglers —
// into the group their circle named, else the default.

import Foundation
import SwiftData

enum Groups {
    static let seeds: [(name: String, cadenceDays: Int?)] = [
        ("Inner", 7), ("Close", 30), ("Friends", 90), ("Acquaintances", 365), ("No nudges", nil),
    ]

    @MainActor
    static func ensureSeeded(context: ModelContext) {
        var groups = all(context: context)
        if groups.isEmpty {
            for (i, seed) in seeds.enumerated() {
                context.insert(FriendGroup(name: seed.name, cadenceDays: seed.cadenceDays, order: i))
            }
            groups = all(context: context)
        }
        let orphans = (try? context.fetch(FetchDescriptor<Friend>(predicate: #Predicate { $0.group == nil }))) ?? []
        for friend in orphans {
            let circleName = FriendCircle(rawValue: friend.circleRaw)?.label
            friend.group = groups.first { $0.name == circleName } ?? defaultGroup(groups)
        }
        if context.hasChanges { try? context.save() }
    }

    @MainActor
    static func all(context: ModelContext) -> [FriendGroup] {
        (try? context.fetch(FetchDescriptor<FriendGroup>(sortBy: [SortDescriptor(\.order)]))) ?? []
    }

    /// Where a new friend lands until told otherwise.
    static func defaultGroup(_ groups: [FriendGroup]) -> FriendGroup? {
        groups.first { $0.name == "Friends" } ?? groups.first
    }
}
