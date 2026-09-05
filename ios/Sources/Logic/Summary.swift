// What to remember about someone right now, from what has been logged.
// The input is plain values so the composition is testable; the
// heuristic here is always available, and the on-device model
// (Services/Summaries.swift) writes prose from the same brief.

import Foundation

struct SummaryInput: Equatable {
    struct FactLine: Equatable {
        let label: String
        let value: String
    }

    struct EntryLine: Equatable {
        let date: Date
        let kind: String
        let text: String
        let countsAsContact: Bool
    }

    struct ReminderLine: Equatable {
        let title: String
        let due: Date
    }

    var name: String
    var circle: String
    var facts: [FactLine]
    /// Newest first.
    var entries: [EntryLine]
    /// Open, soonest first.
    var reminders: [ReminderLine]
}

enum HeuristicSummary {
    /// The most notes the brief carries, and the most of each: an on-device
    /// model's window is small, and the newest notes are the ones that
    /// matter.
    static let maxEntries = 12
    static let maxEntryChars = 400

    /// A structured summary: standing, facts, the latest notes, what is
    /// coming up. Empty when there is nothing to say.
    static func compose(_ input: SummaryInput, now: Date, calendar: Calendar = .current) -> String {
        var lines: [String] = []

        var standing = "\(input.circle) friend"
        if let last = input.entries.first(where: \.countsAsContact) {
            standing += " · last talked \(Dates.since(last.date, now: now, calendar: calendar)) (\(last.kind.lowercased()))"
        } else if !input.entries.isEmpty {
            standing += " · notes only, no conversation logged yet"
        }
        lines.append(standing + ".")

        let facts = input.facts.prefix(6).map { "\($0.label) \($0.value)" }
        if !facts.isEmpty { lines.append(facts.joined(separator: " · ") + ".") }

        let recent = input.entries.prefix(2).compactMap { entry -> String? in
            let gist = firstSentence(entry.text)
            guard !gist.isEmpty else { return nil }
            return entry.date.formatted(.dateTime.month(.abbreviated).day()) + " — " + gist
        }
        if !recent.isEmpty { lines.append("Lately: " + recent.joined(separator: " ")) }

        let next = input.reminders.prefix(2).map {
            "\($0.title) (\($0.due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())))"
        }
        if !next.isEmpty { lines.append("Up next: " + next.joined(separator: "; ") + ".") }

        // A standing line alone says nothing the row above it doesn't.
        return lines.count > 1 ? lines.joined(separator: "\n") : ""
    }

    /// The same facts as text for a language model: dated, newest first,
    /// bounded.
    static func brief(_ input: SummaryInput, now: Date) -> String {
        var out = ["Friend: \(input.name) (\(input.circle.lowercased()) circle)."]
        if !input.facts.isEmpty {
            out.append("Facts: " + input.facts.map { "\($0.label): \($0.value)" }.joined(separator: "; ") + ".")
        }
        if !input.entries.isEmpty {
            out.append("Notes, newest first:")
            for entry in input.entries.prefix(maxEntries) {
                let text = entry.text.count > maxEntryChars ? String(entry.text.prefix(maxEntryChars)) + "…" : entry.text
                let ago = Dates.since(entry.date, now: now)
                out.append("- \(entry.date.formatted(.iso8601.year().month().day())) (\(ago), \(entry.kind.lowercased())): \(text)")
            }
        }
        if !input.reminders.isEmpty {
            out.append("Open follow-ups: " + input.reminders.map {
                "\($0.title) due \($0.due.formatted(.iso8601.year().month().day()))"
            }.joined(separator: "; ") + ".")
        }
        return out.joined(separator: "\n")
    }

    /// Up to the first sentence, capped, so a paragraph of a note reads as
    /// one line.
    static func firstSentence(_ text: String, cap: Int = 140) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var first = trimmed
        if let end = trimmed.firstIndex(where: { ".!?\n".contains($0) }) {
            first = String(trimmed[...end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if first.hasSuffix("\n") { first.removeLast() }
        }
        return first.count > cap ? String(first.prefix(cap)).trimmingCharacters(in: .whitespaces) + "…" : first
    }
}
