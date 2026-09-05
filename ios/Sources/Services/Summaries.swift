// Keeps each friend's summary current: rebuilt after a log is filed, by
// the on-device model when there is one, otherwise from the same brief
// by hand. One rebuild per friend at a time; the page shows the wait.

import Foundation
import Observation
import SwiftData

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
@Observable
final class SummaryEngine {
    static let shared = SummaryEngine()

    private(set) var inFlight: Set<UUID> = []

    func refresh(all friends: [Friend], context: ModelContext) {
        for friend in friends {
            Task { await refresh(friend, context: context) }
        }
    }

    func refresh(_ friend: Friend, context: ModelContext, now: Date = Date()) async {
        guard inFlight.insert(friend.id).inserted else { return }
        defer { inFlight.remove(friend.id) }
        let input = Self.input(for: friend)
        var text: String?
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), FoundationExtractor.isAvailable, !input.entries.isEmpty {
            text = try? await FoundationSummarizer.summarize(input, now: now)
        }
        #endif
        let cleaned = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        friend.summary = cleaned.isEmpty ? HeuristicSummary.compose(input, now: now) : cleaned
        friend.summaryUpdatedAt = now
        try? context.save()
    }

    static func input(for friend: Friend) -> SummaryInput {
        SummaryInput(
            name: friend.displayName,
            circle: friend.circle.label,
            facts: friend.sortedFacts.map { .init(label: $0.label, value: $0.value) },
            entries: friend.sortedEntries.prefix(HeuristicSummary.maxEntries).map {
                .init(date: $0.date, kind: $0.kind.label, text: $0.body, countsAsContact: $0.kind.countsAsContact)
            },
            reminders: friend.openReminders.map { .init(title: $0.title, due: $0.due) })
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
enum FoundationSummarizer {
    static func summarize(_ input: SummaryInput, now: Date) async throws -> String {
        let session = LanguageModelSession(instructions: """
            You keep a short private briefing about one friend, for the person who wrote the notes. \
            Write two to four plain sentences about the friend, in the third person, addressed to the note-writer. \
            Use only the notes and facts given and never invent anything. Prefer what is recent and what is coming up. \
            No headings, no bullet points, no preamble — just the sentences.
            """)
        let today = now.formatted(.iso8601.year().month().day())
        let prompt = "Today is \(today).\n\n" + HeuristicSummary.brief(input, now: now)
        return try await session.respond(to: prompt).content
    }
}
#endif
