// A group of friends, with the cadence its members inherit. The five
// built-in circles are seeded as groups on first launch (Services/Groups
// .swift) and are ordinary groups from then on: renamed, re-paced, or
// deleted like any the reader makes.

import Foundation
import SwiftData

@Model
final class FriendGroup {
    var id: UUID = UUID()
    var name: String = ""
    /// nil means members are never nudged.
    var cadenceDays: Int?
    var order: Int = 0
    var createdAt: Date = Date()
    /// Inverse of the one-group-per-friend relationship this app started
    /// with; only the migration reads it.
    @Relationship(inverse: \Friend.group) var friends: [Friend]?
    @Relationship(inverse: \Friend.groups) var members: [Friend]?

    init(name: String, cadenceDays: Int?, order: Int) {
        self.name = name
        self.cadenceDays = cadenceDays
        self.order = order
    }
}

extension FriendGroup {
    var cadenceLabel: String { cadenceDays.map { "\($0)d" } ?? "—" }

    var cadenceSentence: String { cadenceDays.map { "every \($0)d" } ?? "no nudges" }

    var memberCount: Int { (members ?? []).filter { !$0.archived }.count }

    var memberSentence: String { memberCount == 1 ? "1 person" : "\(memberCount) people" }

    /// Members with no other group — the ones a deletion has to re-home.
    var soleMembers: [Friend] {
        (members ?? []).filter { ($0.groups ?? []).count <= 1 }
    }
}
