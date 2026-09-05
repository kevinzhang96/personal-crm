// The People search box, as a language: words match anything about a
// person; `key:value` narrows to one property; `#tag` is a tag; terms
// AND together. Pure over a plain snapshot of a friend, so the rules are
// tested here and the list only asks "does this one match".

import Foundation

struct PeopleQuery: Equatable {
    enum Term: Equatable {
        case text(String)
        case scoped(key: String, value: String)
    }

    var terms: [Term]

    var isEmpty: Bool { terms.isEmpty }

    /// Notes are the expensive field to gather; only a free word or a
    /// note-scoped term reads them.
    var needsNotes: Bool {
        terms.contains {
            switch $0 {
            case .text: true
            case .scoped(let key, _): Self.noteKeys.contains(key)
            }
        }
    }

    /// Tokens split on whitespace, with double quotes holding a phrase
    /// together: `lives:"long island city" #college works:figma`.
    static func parse(_ raw: String) -> PeopleQuery {
        var terms: [Term] = []
        for token in tokens(raw) {
            let lower = token.lowercased()
            if lower.hasPrefix("#"), lower.count > 1 {
                terms.append(.scoped(key: "tag", value: String(lower.dropFirst())))
            } else if let colon = lower.firstIndex(of: ":"), colon != lower.startIndex {
                let key = String(lower[..<colon])
                let value = String(lower[lower.index(after: colon)...]).trimmingCharacters(in: quotes)
                terms.append(.scoped(key: key, value: value))
            } else if !lower.isEmpty {
                terms.append(.text(lower.trimmingCharacters(in: quotes)))
            }
        }
        return PeopleQuery(terms: terms)
    }

    func matches(_ friend: SearchableFriend) -> Bool {
        terms.allSatisfy { term in
            switch term {
            case .text(let word):
                return friend.everything.contains { $0.has(word) }
            case .scoped(let key, let value):
                return Self.match(key: key, value: value, in: friend)
            }
        }
    }

    // MARK: rules

    private static let tagKeys: Set<String> = ["tag", "tags"]
    private static let groupKeys: Set<String> = ["group", "in", "circle"]
    private static let placeKeys: Set<String> = ["lives", "live", "location", "loc", "city", "where"]
    private static let metKeys: Set<String> = ["met"]
    private static let nameKeys: Set<String> = ["name", "called"]
    private static let noteKeys: Set<String> = ["note", "notes", "said", "mentioned", "log"]
    private static let starKeys: Set<String> = ["star", "starred"]
    private static let quotes = CharacterSet(charactersIn: "\"“”")

    private static func match(key: String, value: String, in f: SearchableFriend) -> Bool {
        switch key {
        case _ where tagKeys.contains(key):
            return value.isEmpty ? !f.tags.isEmpty : f.tags.contains { $0.has(value) }
        case _ where groupKeys.contains(key):
            return f.groups.contains { $0.has(value) }
        case _ where placeKeys.contains(key):
            return f.location.has(value) || f.facts.contains { $0.label.has("live") && $0.value.has(value) }
        case _ where metKeys.contains(key):
            return f.howWeMet.has(value) || f.facts.contains { $0.label.has("met") && $0.value.has(value) }
        case _ where nameKeys.contains(key):
            return f.name.has(value) || f.nickname.has(value)
        case _ where noteKeys.contains(key):
            return f.notes.contains { $0.has(value) }
        case _ where starKeys.contains(key):
            let wantsUnstarred = ["no", "false", "0"].contains(value)
            return wantsUnstarred ? !f.starred : f.starred
        default:
            // Any other key is a fact label: works:figma, partner:, gift:kettle.
            return f.facts.contains { $0.label.has(key) && (value.isEmpty || $0.value.has(value)) }
        }
    }

    private static func tokens(_ raw: String) -> [String] {
        var out: [String] = []
        var current = ""
        var quoted = false
        for ch in raw {
            if ch == "\"" || ch == "“" || ch == "”" {
                quoted.toggle()
            } else if ch.isWhitespace, !quoted {
                if !current.isEmpty { out.append(current) }
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

/// What a friend is, for searching: plain strings, gathered once per
/// keystroke by the list.
struct SearchableFriend {
    struct FactPair {
        let label: String
        let value: String
    }

    var name: String
    var nickname: String = ""
    var tags: [String] = []
    var location: String = ""
    var howWeMet: String = ""
    var about: String = ""
    var groups: [String] = []
    var facts: [FactPair] = []
    var notes: [String] = []
    var starred = false

    /// Every field a bare word may hit.
    var everything: [String] {
        [name, nickname, location, howWeMet, about] + tags + groups
            + facts.map { "\($0.label) \($0.value)" } + notes
    }
}

private extension String {
    /// Case- and accent-insensitive containment; an empty needle matches nothing.
    func has(_ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        return range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
