// The person, and the rules of the store's shape: every relationship
// optional, every property defaulted, no unique attributes — so CloudKit
// sync can be switched on later without a migration (docs/DESIGN.md §3).

import Foundation
import SwiftData

/// How close someone is, which is the app's default for how often to be
/// in touch. `none` means the friend is kept but never nudged.
enum FriendCircle: String, Codable, CaseIterable, Identifiable {
    case inner, close, friends, acquaintances, none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inner: "Inner"
        case .close: "Close"
        case .friends: "Friends"
        case .acquaintances: "Acquaintances"
        case .none: "No nudges"
        }
    }

    var defaultCadenceDays: Int? {
        switch self {
        case .inner: 7
        case .close: 30
        case .friends: 90
        case .acquaintances: 365
        case .none: nil
        }
    }
}

@Model
final class Friend {
    var id: UUID = UUID()
    var displayName: String = ""
    var givenName: String = ""
    var familyName: String = ""
    var nickname: String = ""
    @Attribute(.externalStorage) var photo: Data?
    /// The linked CNContact, for refreshing name/photo/methods from it.
    var contactIdentifier: String?
    var circleRaw: String = FriendCircle.friends.rawValue
    /// Overrides the circle's default cadence when set.
    var cadenceDays: Int?
    /// "Not now": hidden from nudges and the digest until this passes.
    var snoozedUntil: Date?
    var tags: [String] = []
    var location: String = ""
    var timeZoneIdentifier: String?
    var howWeMet: String = ""
    var about: String = ""
    var archived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ContactMethod.friend) var methods: [ContactMethod]?
    @Relationship(inverse: \Entry.friends) var entries: [Entry]?
    @Relationship(deleteRule: .cascade, inverse: \Fact.friend) var facts: [Fact]?
    @Relationship(deleteRule: .cascade, inverse: \Reminder.friend) var reminders: [Reminder]?
    @Relationship(deleteRule: .cascade, inverse: \ImportantDate.friend) var dates: [ImportantDate]?

    init(displayName: String = "", circle: FriendCircle = .friends) {
        self.displayName = displayName
        self.circleRaw = circle.rawValue
    }
}

extension Friend {
    var circle: FriendCircle {
        get { FriendCircle(rawValue: circleRaw) ?? .friends }
        set { circleRaw = newValue.rawValue }
    }

    var effectiveCadenceDays: Int? { cadenceDays ?? circle.defaultCadenceDays }

    /// Derived from entries, never stored: the newest entry that counts as
    /// actually being in touch (a note about someone is not a conversation).
    var lastContact: Date? {
        entries?.lazy.filter { $0.kind.countsAsContact }.map(\.date).max()
    }

    func status(now: Date) -> ContactStatus {
        Cadence.status(
            lastContact: lastContact, cadenceDays: effectiveCadenceDays,
            snoozedUntil: snoozedUntil, createdAt: createdAt, now: now)
    }

    var initials: String { Self.initials(of: displayName) }

    static func initials(of name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    var birthday: ImportantDate? {
        dates?.first { $0.label.caseInsensitiveCompare(ImportantDate.birthdayLabel) == .orderedSame }
    }

    /// Preferred first, then the order the kinds are declared, so the row of
    /// contact buttons is stable across screens.
    var sortedMethods: [ContactMethod] {
        (methods ?? []).sorted {
            if $0.preferred != $1.preferred { return $0.preferred }
            return $0.kind.order < $1.kind.order
        }
    }

    var openReminders: [Reminder] {
        (reminders ?? []).filter { !$0.done }.sorted { $0.due < $1.due }
    }

    var sortedEntries: [Entry] {
        (entries ?? []).sorted { $0.date > $1.date }
    }

    /// The common labels in their usual order, then anything else by name.
    var sortedFacts: [Fact] {
        func rank(_ f: Fact) -> Int {
            Fact.commonLabels.firstIndex { $0.caseInsensitiveCompare(f.label) == .orderedSame } ?? Fact.commonLabels.count
        }
        return (facts ?? []).sorted { (rank($0), $0.label) < (rank($1), $1.label) }
    }
}
