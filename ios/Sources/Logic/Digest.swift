// The daily digest: who is overdue on a given day, and the one
// notification that says so. Pure over plain values so the notifier can
// ask about each of the next seven mornings.

import Foundation

struct DigestCandidate: Equatable {
    let name: String
    let lastContact: Date?
    let cadenceDays: Int?
    let snoozedUntil: Date?
    let createdAt: Date
}

struct DigestLine: Equatable {
    let name: String
    let overdueDays: Int
}

struct DigestContent: Equatable {
    let title: String
    let body: String
}

enum Digest {
    /// Longest overdue first; ties by name so the order is stable.
    static func overdue(_ candidates: [DigestCandidate], on day: Date, calendar: Calendar = .current) -> [DigestLine] {
        candidates.compactMap { candidate in
            let status = Cadence.status(
                lastContact: candidate.lastContact, cadenceDays: candidate.cadenceDays,
                snoozedUntil: candidate.snoozedUntil, createdAt: candidate.createdAt,
                now: day, calendar: calendar)
            guard case .overdue(let days) = status else { return nil }
            return DigestLine(name: candidate.name, overdueDays: days)
        }
        .sorted { ($0.overdueDays, $1.name) > ($1.overdueDays, $0.name) }
    }

    /// Nothing overdue is no notification at all, never an empty one.
    static func content(for lines: [DigestLine]) -> DigestContent? {
        guard let first = lines.first else { return nil }
        if lines.count == 1 {
            return DigestContent(
                title: "Catch up with \(first.name)",
                body: "\(first.overdueDays)d past your usual — say hi?")
        }
        let shown = lines.prefix(3).map { "\($0.name) · \($0.overdueDays)d" }
        let rest = lines.count - shown.count
        let body = shown.joined(separator: ", ") + (rest > 0 ? " +\(rest) more" : "")
        return DigestContent(title: "Catch up with \(lines.count) friends", body: body)
    }
}
