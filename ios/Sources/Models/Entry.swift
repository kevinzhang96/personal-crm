// One item on a friend's timeline: a conversation of some kind, or a note
// about them. The kind decides whether it counts as being in touch.

import Foundation
import SwiftData

enum EntryKind: String, Codable, CaseIterable, Identifiable {
    case call, video, inPerson, message, email, social, note

    var id: String { rawValue }

    /// A note is something learned, not a conversation had; it must never
    /// reset the "last talked" clock.
    var countsAsContact: Bool { self != .note }

    var label: String {
        switch self {
        case .call: "Call"
        case .video: "Video"
        case .inPerson: "In person"
        case .message: "Message"
        case .email: "Email"
        case .social: "Social"
        case .note: "Note"
        }
    }

    var icon: String {
        switch self {
        case .call: "phone"
        case .video: "video"
        case .inPerson: "person.2"
        case .message: "message"
        case .email: "envelope"
        case .social: "at"
        case .note: "note.text"
        }
    }
}

@Model
final class Entry {
    var id: UUID = UUID()
    var date: Date = Date()
    var kindRaw: String = EntryKind.note.rawValue
    var text: String = ""
    /// What the recogniser heard, kept apart from `text` so the reader's
    /// edits never destroy the original.
    var transcript: String = ""
    /// The recording, carried by the store (and so by iCloud); external
    /// storage keeps it out of the row.
    @Attribute(.externalStorage) var audio: Data?
    /// The cache file's name (AudioStore); also how recordings were kept
    /// before they lived in the store.
    var audioFile: String?
    var durationSeconds: Double?
    var createdAt: Date = Date()
    var friends: [Friend]?
    @Relationship(inverse: \Fact.source) var facts: [Fact]?
    @Relationship(inverse: \Reminder.source) var reminders: [Reminder]?

    init(kind: EntryKind = .note, date: Date = Date(), text: String = "") {
        self.kindRaw = kind.rawValue
        self.date = date
        self.text = text
    }
}

extension Entry {
    var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    /// The reader's words if there are any, else what was heard.
    var body: String { text.isEmpty ? transcript : text }

    var hasAudio: Bool { audio != nil || (audioFile.map(AudioStore.exists) ?? false) }

    var friendNames: String {
        (friends ?? []).map(\.displayName).sorted().joined(separator: ", ")
    }
}
