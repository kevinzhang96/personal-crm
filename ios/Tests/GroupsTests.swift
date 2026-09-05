// Seeding and the migration from circles, against an in-memory store.

import Foundation
import SwiftData
import Testing
@testable import Tend

@MainActor
struct GroupsTests {
    @Test("first launch seeds the five circles as groups, and a friend lands in the one their circle named")
    func seedsAndMigrates() throws {
        let container = try Store.container(inMemory: true)
        let context = container.mainContext
        let priya = Friend(displayName: "Priya", circle: .close)
        let nobody = Friend(displayName: "N", circle: .none)
        context.insert(priya)
        context.insert(nobody)
        Groups.ensureSeeded(context: context)
        let groups = Groups.all(context: context)
        #expect(groups.map(\.name) == ["Inner", "Close", "Friends", "Acquaintances", "No nudges"])
        #expect(groups.map(\.cadenceDays) == [7, 30, 90, 365, nil])
        #expect(priya.group?.name == "Close")
        #expect(priya.effectiveCadenceDays == 30)
        #expect(nobody.group?.name == "No nudges")
        #expect(nobody.effectiveCadenceDays == nil)
    }

    @Test("seeding again changes nothing, and a friend left without a group gets the default")
    func idempotentAndOrphans() throws {
        let container = try Store.container(inMemory: true)
        let context = container.mainContext
        Groups.ensureSeeded(context: context)
        Groups.ensureSeeded(context: context)
        #expect(Groups.all(context: context).count == 5)
        let friend = Friend(displayName: "Sam")
        friend.circleRaw = "something-old"
        context.insert(friend)
        Groups.ensureSeeded(context: context)
        #expect(friend.group?.name == "Friends")
    }
}
