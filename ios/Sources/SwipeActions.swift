// The quick actions a People row swipe can carry, and the reader's choice
// of which rides each edge. Swiping is a platform idiom, so the
// assignment is a device preference (UserDefaults), not data — the
// actions themselves still do their work through the store.

import SwiftUI

enum SwipeAction: String, CaseIterable, Identifiable {
    case log
    case snooze
    case archive
    case delete

    var id: String { rawValue }

    /// What the settings screen calls the action; the swipe button names
    /// itself in context (an archived friend offers "Unarchive").
    var label: String {
        switch self {
        case .log: "Log a call"
        case .snooze: "Snooze 2 weeks"
        case .archive: "Archive"
        case .delete: "Delete"
        }
    }

    var icon: String {
        switch self {
        case .log: "square.and.pencil"
        case .snooze: "zzz"
        case .archive: "archivebox"
        case .delete: "trash"
        }
    }

    var tint: Color {
        switch self {
        case .log: Theme.accent
        case .snooze: .indigo
        case .archive: .gray
        case .delete: .red
        }
    }

    /// Delete asks first, however it was reached: a full swipe is one
    /// motion, and a friend's notes and reminders go with them.
    var isDestructive: Bool { self == .delete }

    // Both screens that speak this preference — the settings picker and
    // the rows obeying it — read it through these, so the key and the
    // out-of-box assignment exist once.
    static let leadingKey = "swipeLeading"
    static let trailingKey = "swipeTrailing"
    static let defaultLeading = SwipeAction.log.rawValue
    static let defaultTrailing = SwipeAction.snooze.rawValue

    /// An edge carries one action. The stored form is its raw value, and
    /// an empty string is a deliberately bare edge, not a fall back to
    /// the default.
    static func store(_ action: SwipeAction?) -> String {
        action?.rawValue ?? ""
    }

    /// The action on an edge; a raw value this build no longer knows is a
    /// bare edge, not a crash.
    static func one(_ raw: String) -> SwipeAction? {
        SwipeAction(rawValue: raw)
    }
}
