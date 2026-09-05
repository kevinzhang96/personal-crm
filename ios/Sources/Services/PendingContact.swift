// The tap that left the app to call or message someone. Remembered so
// that coming back can ask "did you reach them?" — and forgotten after a
// few hours, when the answer is no longer about that tap.

import Foundation
import UIKit

enum PendingContact {
    private static let key = "pendingContact"
    private static let maxAge: TimeInterval = 6 * 3600

    struct Attempt {
        let friendId: UUID
        let kind: EntryKind
        let at: Date
    }

    @MainActor
    static func open(_ url: URL, kind: ContactKind, friendId: UUID) {
        UserDefaults.standard.set(
            ["friend": friendId.uuidString, "kind": ContactLinks.entryKind(for: kind).rawValue, "at": Date().timeIntervalSince1970],
            forKey: key)
        UIApplication.shared.open(url)
    }

    /// The attempt, once — reading clears it.
    static func take(now: Date = Date()) -> Attempt? {
        defer { UserDefaults.standard.removeObject(forKey: key) }
        guard let stored = UserDefaults.standard.dictionary(forKey: key),
              let id = (stored["friend"] as? String).flatMap(UUID.init),
              let kind = (stored["kind"] as? String).flatMap(EntryKind.init),
              let at = stored["at"] as? TimeInterval
        else { return nil }
        let date = Date(timeIntervalSince1970: at)
        guard now.timeIntervalSince(date) < maxAge else { return nil }
        return Attempt(friendId: id, kind: kind, at: date)
    }
}
