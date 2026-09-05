// Seeding, the migrations from circles and from one-group-per-friend,
// and the cadence a friend in several groups gets — against an in-memory store.

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
        #expect(priya.sortedGroups.map(\.name) == ["Close"])
        #expect(priya.effectiveCadenceDays == 30)
        #expect(nobody.sortedGroups.map(\.name) == ["No nudges"])
        #expect(nobody.effectiveCadenceDays == nil)
    }

    @Test("a friend with the earlier single group is moved into groups, and one with none gets the default")
    func legacyAndOrphans() throws {
        let container = try Store.container(inMemory: true)
        let context = container.mainContext
        Groups.ensureSeeded(context: context)
        let groups = Groups.all(context: context)
        let legacy = Friend(displayName: "L")
        legacy.group = groups[0]
        let orphan = Friend(displayName: "O")
        orphan.circleRaw = "something-old"
        context.insert(legacy)
        context.insert(orphan)
        Groups.ensureSeeded(context: context)
        #expect(legacy.sortedGroups.map(\.name) == ["Inner"])
        #expect(legacy.group == nil)
        #expect(orphan.sortedGroups.map(\.name) == ["Friends"])
        Groups.ensureSeeded(context: context)
        #expect(Groups.all(context: context).count == 5)
    }

    @Test("in several groups, the tightest cadence applies; only no-nudge groups means never; the override wins")
    func cadenceAcrossGroups() throws {
        let container = try Store.container(inMemory: true)
        let context = container.mainContext
        Groups.ensureSeeded(context: context)
        let groups = Groups.all(context: context)
        let friend = Friend(displayName: "F")
        context.insert(friend)
        friend.groups = [groups[2], groups[0]]           // Friends 90, Inner 7
        #expect(friend.effectiveCadenceDays == 7)
        #expect(friend.groupNames == "Inner, Friends")
        friend.groups = [groups[4]]                      // No nudges
        #expect(friend.effectiveCadenceDays == nil)
        friend.groups = [groups[4], groups[3]]           // No nudges + Acquaintances
        #expect(friend.effectiveCadenceDays == 365)
        friend.cadenceDays = 14
        #expect(friend.effectiveCadenceDays == 14)
        #expect(groups[3].soleMembers.isEmpty, "F is also in No nudges")
        friend.groups = [groups[3]]
        #expect(groups[3].soleMembers.map(\.displayName) == ["F"])
    }
}
