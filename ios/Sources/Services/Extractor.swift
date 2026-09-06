// Which extractor answers: the on-device language model when the device
// has one, with a second model session judging its answer; otherwise the
// heuristic alone. Either way the result is a proposal the reader accepts
// or dismisses — the loop and its rules are Logic/JudgeLoop.swift and
// Logic/Grounding.swift; this file is the model behind the protocols and
// the settings that shape it.

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The reader's say over the model: the two prompts, whether the judge
/// runs, and how many times. Device preferences, read fresh per note.
struct SuggestionSettings: Equatable {
    static let extractorKey = "suggestions.extractorPrompt"
    static let judgeKey = "suggestions.judgePrompt"
    static let judgeEnabledKey = "suggestions.judgeEnabled"
    static let roundsKey = "suggestions.judgeRounds"

    var extractorPrompt = Prompts.extractor
    var judgePrompt = Prompts.judge
    var judgeEnabled = true
    var rounds = Prompts.defaultRounds

    /// An empty prompt in the store means the reader cleared it, which
    /// is not a prompt; the default answers instead.
    static func load(from defaults: UserDefaults = .standard) -> SuggestionSettings {
        var s = SuggestionSettings()
        if let text = defaults.string(forKey: extractorKey), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            s.extractorPrompt = text
        }
        if let text = defaults.string(forKey: judgeKey), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            s.judgePrompt = text
        }
        if defaults.object(forKey: judgeEnabledKey) != nil { s.judgeEnabled = defaults.bool(forKey: judgeEnabledKey) }
        if defaults.object(forKey: roundsKey) != nil {
            s.rounds = min(max(defaults.integer(forKey: roundsKey), Prompts.roundsRange.lowerBound), Prompts.roundsRange.upperBound)
        }
        return s
    }
}

enum SuggestionEngine {
    static func suggestions(for text: String, now: Date = Date(), settings: SuggestionSettings = .load(),
                            progress: (JudgeLoop.Stage) -> Void = { _ in }) async -> JudgeOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return .empty }
        let loop = JudgeLoop(maxRounds: settings.judgeEnabled ? settings.rounds : 0)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), FoundationProposer.isAvailable {
            let proposer = FoundationProposer(instructions: settings.extractorPrompt)
            let judge = settings.judgeEnabled ? FoundationJudge(instructions: settings.judgePrompt) : nil
            if var outcome = try? await loop.run(note: trimmed, now: now, proposer: proposer, judge: judge, progress: progress) {
                outcome.modelled = true
                return outcome
            }
        }
        #endif
        return (try? await loop.run(note: trimmed, now: now, proposer: HeuristicExtractor(), judge: nil, progress: progress)) ?? .empty
    }

    static var usesLanguageModel: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return FoundationProposer.isAvailable }
        #endif
        return false
    }
}

#if canImport(FoundationModels)

@available(iOS 26.0, *)
@Generable
struct ExtractedNote {
    @Guide(description: "Specific events in the friend's own life that the note says are coming up or have just happened. Usually empty.")
    var events: [ExtractedEvent]
    @Guide(description: "Durable facts about the friend the note states outright: partner, kids, job, city, pet, allergy, a thing they want. Usually empty.")
    var facts: [ExtractedFact]
}

@available(iOS 26.0, *)
@Generable
struct ExtractedEvent {
    @Guide(description: "One short imperative sentence saying what to ask the friend about after the event, naming the event in the note's own words")
    var followUp: String
    @Guide(description: "The event's day as YYYY-MM-DD copied from the calendar given, or empty when the note names no day")
    var eventDate: String
    @Guide(description: "The sentence from the note that mentions the event, copied word for word")
    var evidence: String
}

@available(iOS 26.0, *)
@Generable
struct ExtractedFact {
    @Guide(description: "A short label such as Partner, Kids, Works at, Lives in, Likes, Gift idea, Allergy, Pets")
    var label: String
    @Guide(description: "The value, in the note's own words and as brief as they allow")
    var value: String
}

@available(iOS 26.0, *)
@Generable
struct JudgeReport {
    @Guide(description: "One verdict per numbered proposal")
    var verdicts: [JudgeVerdict]
}

@available(iOS 26.0, *)
@Generable
struct JudgeVerdict {
    @Guide(description: "The proposal's number in the list")
    var number: Int
    @Guide(description: "True to keep the proposal, false to reject it")
    var keep: Bool
    @Guide(description: "One short sentence saying what is wrong, when rejecting; empty when keeping")
    var reason: String
}

/// The model's prompt is bounded because its window is: a long
/// transcript is read to this many characters.
private let modelNoteLimit = 2000

/// A dated calendar, because a small model cannot count days.
@available(iOS 26.0, *)
private func datedPreamble(now: Date, calendar: Calendar) -> String {
    let today = now.formatted(.iso8601.year().month().day())
    let weekday = now.formatted(.dateTime.weekday(.wide))
    let days = (-3...21).compactMap { calendar.date(byAdding: .day, value: $0, to: now) }
        .map { $0.formatted(.dateTime.weekday(.abbreviated)) + " " + $0.formatted(.iso8601.year().month().day()) }
    return "Today is \(weekday), \(today).\nCalendar: \(days.joined(separator: ", "))."
}

/// A proposal as one line the model can be told about.
private func describe(_ s: Suggestion) -> String {
    if let due = s.dueDate {
        return "Follow-up \"\(s.title)\" on \(due.formatted(.iso8601.year().month().day())), because the note says: \"\(s.detail)\""
    }
    return "Fact \(s.title): \(s.detail)"
}

/// The first session: drafts from the note, and drafts again in the same
/// conversation when the judge sends the draft back.
@available(iOS 26.0, *)
final class FoundationProposer: SuggestionProposer {
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    private let session: LanguageModelSession
    private let calendar = Calendar.current

    init(instructions: String) {
        session = LanguageModelSession(instructions: instructions)
    }

    func propose(note: String, now: Date) async throws -> [Suggestion] {
        let prompt = datedPreamble(now: now, calendar: calendar) + "\n\nNote:\n" + note.prefix(modelNoteLimit)
        return suggestions(from: try await session.respond(to: prompt, generating: ExtractedNote.self).content, now: now)
    }

    func revise(note: String, kept: [Suggestion], rejected: [Rejection], now: Date) async throws -> [Suggestion] {
        let critique = rejected.map { "- \(describe($0.suggestion)) — \($0.reason)" }.joined(separator: "\n")
        let standing = kept.isEmpty ? "Nothing else stood." : "Still standing:\n" + kept.map { "- " + describe($0) }.joined(separator: "\n")
        let prompt = """
            A reviewer read your answer against the note and rejected these:
            \(critique)
            \(standing)

            Answer again from the note alone: keep what stood, leave out what was rejected, and add nothing the note does not state. \
            An emptier answer is fine.
            """
        return suggestions(from: try await session.respond(to: prompt, generating: ExtractedNote.self).content, now: now)
    }

    /// The model's answer as proposals, taken at its word: Grounding reads
    /// each against the note, resolves the day from the sentence, and
    /// drops what the note does not say.
    private func suggestions(from extracted: ExtractedNote, now: Date) -> [Suggestion] {
        var out: [Suggestion] = []
        for event in extracted.events where !event.followUp.isEmpty {
            let due = HeuristicExtractor.followUpDue(after: Self.parse(event.eventDate, calendar: calendar), now: now, calendar: calendar)
            out.append(.followUp(event.followUp, due: due, because: event.evidence))
        }
        for fact in extracted.facts {
            out.append(.fact(fact.label.trimmingCharacters(in: .whitespacesAndNewlines),
                             fact.value.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return out
    }

    private static func parse(_ ymd: String, calendar: Calendar) -> Date? {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

/// The second session: a fresh one each round, so it reads the list in
/// front of it and not its own earlier verdicts.
@available(iOS 26.0, *)
struct FoundationJudge: SuggestionJudge {
    let instructions: String
    private let calendar = Calendar.current

    init(instructions: String) {
        self.instructions = instructions
    }

    func review(note: String, proposals: [Suggestion], now: Date) async throws -> [Rejection] {
        let session = LanguageModelSession(instructions: instructions)
        let listing = proposals.enumerated().map { "\($0.offset + 1). \(describe($0.element))" }.joined(separator: "\n")
        let prompt = datedPreamble(now: now, calendar: calendar) + "\n\nNote:\n" + note.prefix(modelNoteLimit) + "\n\nProposals:\n" + listing
        let report = try await session.respond(to: prompt, generating: JudgeReport.self).content
        return report.verdicts.compactMap { verdict in
            guard !verdict.keep, proposals.indices.contains(verdict.number - 1) else { return nil }
            let reason = verdict.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return Rejection(suggestion: proposals[verdict.number - 1], reason: reason.isEmpty ? "the reviewer set it aside" : reason)
        }
    }
}

#endif
