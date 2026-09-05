// Something worth remembering about a friend, as a label and a value —
// "Partner: Maya", "Works at: Stripe", "Gift idea: pour-over kettle".

import Foundation
import SwiftData

@Model
final class Fact {
    var id: UUID = UUID()
    var label: String = ""
    var value: String = ""
    var updatedAt: Date = Date()
    var friend: Friend?
    /// The entry it was learned from, when it was.
    var source: Entry?

    init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

extension Fact {
    /// The labels the editor offers first; anything else is typed.
    static let commonLabels = [
        "Partner", "Kids", "Works at", "Role", "Lives in", "Hometown", "Likes",
        "Dislikes", "Gift idea", "Working on", "Allergy", "Pets", "Met through",
    ]
}
