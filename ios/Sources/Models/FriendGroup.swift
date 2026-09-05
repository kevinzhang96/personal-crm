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
    @Relationship(inverse: \Friend.group) var friends: [Friend]?

    init(name: String, cadenceDays: Int?, order: Int) {
        self.name = name
        self.cadenceDays = cadenceDays
        self.order = order
    }
}

extension FriendGroup {
    var cadenceLabel: String { cadenceDays.map { "\($0)d" } ?? "—" }

    var cadenceSentence: String { cadenceDays.map { "every \($0)d" } ?? "no nudges" }

    var memberCount: Int { (friends ?? []).filter { !$0.archived }.count }
}
