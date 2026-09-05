// A follow-up: something to do about a friend on a date. One local
// notification per open reminder, scheduled by Notifier.

import Foundation
import SwiftData

enum ReminderKind: String, Codable, CaseIterable {
    case followUp, custom, birthday
}

@Model
final class Reminder {
    var id: UUID = UUID()
    var title: String = ""
    var due: Date = Date()
    var note: String = ""
    var done: Bool = false
    var doneAt: Date?
    var kindRaw: String = ReminderKind.followUp.rawValue
    var createdAt: Date = Date()
    var friend: Friend?
    /// The entry that prompted it, when one did.
    var source: Entry?

    init(title: String, due: Date, note: String = "", kind: ReminderKind = .followUp) {
        self.title = title
        self.due = due
        self.note = note
        self.kindRaw = kind.rawValue
    }
}

extension Reminder {
    var kind: ReminderKind {
        get { ReminderKind(rawValue: kindRaw) ?? .followUp }
        set { kindRaw = newValue.rawValue }
    }

    var notificationId: String { "reminder-\(id.uuidString)" }
}
