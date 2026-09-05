// Which extractor answers: the on-device language model when the device
// has one, otherwise the heuristic. Either way the result is a proposal
// the reader accepts or dismisses — see Logic/Suggestions.swift.

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum SuggestionEngine {
    static func suggestions(for text: String, now: Date = Date()) async -> [Suggestion] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return [] }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), FoundationExtractor.isAvailable,
           let modelled = try? await FoundationExtractor().suggestions(for: trimmed, now: now) {
            return modelled
        }
        #endif
        return HeuristicExtractor().suggestions(for: trimmed, now: now)
    }

    static var usesLanguageModel: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return FoundationExtractor.isAvailable }
        #endif
        return false
    }
}

#if canImport(FoundationModels)

@available(iOS 26.0, *)
@Generable
struct ExtractedNote {
    @Guide(description: "Upcoming or just-happened events the friend mentioned that are worth asking about afterwards. Empty when there are none.")
    var events: [ExtractedEvent]
    @Guide(description: "Durable facts about the friend worth remembering: partner, kids, job, city, likes, gift ideas, allergies. Empty when there are none.")
    var facts: [ExtractedFact]
}

@available(iOS 26.0, *)
@Generable
struct ExtractedEvent {
    @Guide(description: "What to do, as a short to-do addressed to me, e.g. 'Ask how the interview went'")
    var followUp: String
    @Guide(description: "The event's date as YYYY-MM-DD, resolved against today's date; empty when the note gives no date")
    var eventDate: String
    @Guide(description: "The sentence from the note that mentions the event")
    var evidence: String
}

@available(iOS 26.0, *)
@Generable
struct ExtractedFact {
    @Guide(description: "A short label such as Partner, Kids, Works at, Lives in, Likes, Gift idea, Allergy")
    var label: String
    @Guide(description: "The value, as briefly as the note allows")
    var value: String
}

@available(iOS 26.0, *)
struct FoundationExtractor: SuggestionExtractor {
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    func suggestions(for text: String, now: Date) async throws -> [Suggestion] {
        let session = LanguageModelSession(instructions: """
            You read a short note someone wrote about one friend after talking to them. \
            Find events in the friend's life worth asking about after they happen, and durable facts about the friend. \
            Rules: include only what the note states. Never invent a fact; if something is not mentioned, leave it out — \
            never write "none", "unknown" or "N/A". A fact is about the friend, not about other people the note mentions \
            (a partner's employer is not the friend's). Where someone is interviewing is not where they work. \
            For an event's date, copy the exact YYYY-MM-DD from the calendar given; leave it empty if the note gives no day.
            """)
        let calendar = Calendar.current
        let today = now.formatted(.iso8601.year().month().day())
        let weekday = now.formatted(.dateTime.weekday(.wide))
        let days = (-3...21).compactMap { calendar.date(byAdding: .day, value: $0, to: now) }
            .map { $0.formatted(.dateTime.weekday(.abbreviated)) + " " + $0.formatted(.iso8601.year().month().day()) }
        let prompt = "Today is \(weekday), \(today).\nCalendar: \(days.joined(separator: ", ")).\n\nNote:\n\(text)"
        let extracted = try await session.respond(to: prompt, generating: ExtractedNote.self).content
        var out: [Suggestion] = []
        for event in extracted.events where !event.followUp.isEmpty {
            // The sentence itself, resolved here, beats the model's arithmetic.
            let eventDay = (HeuristicExtractor.date(in: event.evidence, now: now, calendar: calendar)
                            ?? Self.parse(event.eventDate, calendar: calendar)).map { max($0, now) }
                ?? calendar.date(byAdding: .day, value: 6, to: now) ?? now
            // A date more than a few days gone is a story, not a follow-up.
            if Dates.daysBetween(eventDay, now, calendar: calendar) > 3 { continue }
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: eventDay)) ?? eventDay
            let due = Dates.at(hour: HeuristicExtractor.followUpHour, on: nextDay, calendar: calendar)
            out.append(.followUp(event.followUp, due: due, because: event.evidence))
        }
        for fact in extracted.facts where Self.isReal(fact.value) && !fact.label.isEmpty {
            out.append(.fact(fact.label, fact.value.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return out.reduce(into: []) { acc, s in
            if !acc.contains(where: { $0.sameAs(s) }) { acc.append(s) }
        }
    }

    /// Small models fill every slot they were told about; a slot filled
    /// with a word for "nothing" is not a fact.
    static func isReal(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?-—"))
        guard !v.isEmpty else { return false }
        let placeholders: Set<String> = ["none", "n/a", "na", "nil", "null", "unknown", "unspecified", "not specified",
                                         "not mentioned", "not given", "not stated", "no", "nothing", "tbd", "?"]
        if placeholders.contains(v) { return false }
        return !["not mentioned", "not specified", "unknown", "no information", "doesn't say", "does not say"].contains { v.contains($0) }
    }

    private static func parse(_ ymd: String, calendar: Calendar) -> Date? {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

#endif
