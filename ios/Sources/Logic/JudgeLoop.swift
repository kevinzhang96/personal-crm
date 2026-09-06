// Propose, review, revise, review — until the reviewer has nothing left
// to say or the rounds run out. The proposer and the judge are whoever
// the shell supplies (the on-device model twice over, or the heuristic
// with no judge at all); the loop itself is pure, and so are the rules
// every round runs through (Grounding). Nothing here creates anything:
// the outcome is still a list of proposals for the reader.

import Foundation

/// Draws proposals from a note, and draws them again when told what was
/// wrong with the first draft.
protocol SuggestionProposer {
    func propose(note: String, now: Date) async throws -> [Suggestion]
    /// A second draft: what stood, and why the rest fell.
    func revise(note: String, kept: [Suggestion], rejected: [Rejection], now: Date) async throws -> [Suggestion]
}

/// Reads proposals against the note and says which should go. Silence
/// about a proposal is consent.
protocol SuggestionJudge {
    func review(note: String, proposals: [Suggestion], now: Date) async throws -> [Rejection]
}

struct JudgeOutcome: Equatable {
    var suggestions: [Suggestion]
    /// Reviews that ran; none without a judge.
    var rounds: Int
    var rejected: [Rejection]
    /// The judge had nothing against what is left. False at the cap,
    /// when the judge could not answer, and when there was no judge.
    var approved: Bool

    static let empty = JudgeOutcome(suggestions: [], rounds: 0, rejected: [], approved: false)
}

struct JudgeLoop {
    enum Stage: Equatable {
        case proposing
        case judging(round: Int)
        case revising(round: Int)
    }

    /// Reviews at most; the last one only trims.
    var maxRounds: Int = Prompts.defaultRounds
    var calendar: Calendar = .current

    func run(note: String, now: Date, proposer: SuggestionProposer, judge: SuggestionJudge?,
             progress: (Stage) -> Void = { _ in }) async throws -> JudgeOutcome {
        progress(.proposing)
        let first = Grounding.review(try await proposer.propose(note: note, now: now), note: note, now: now, calendar: calendar)
        var outcome = JudgeOutcome(suggestions: first.kept, rounds: 0, rejected: first.rejected, approved: false)
        guard let judge, maxRounds > 0 else { return outcome }

        // Once the judge has set a proposal aside it stays aside; a revision
        // that brings it back is overruled without another look.
        var banned: [Suggestion] = []
        while outcome.rounds < maxRounds, !outcome.suggestions.isEmpty {
            outcome.rounds += 1
            progress(.judging(round: outcome.rounds))
            let verdicts: [Rejection]
            do {
                verdicts = try await judge.review(note: note, proposals: outcome.suggestions, now: now)
            } catch {
                // A judge that cannot answer leaves the grounded set as it is.
                break
            }
            let bad = verdicts.filter { r in outcome.suggestions.contains { $0.sameAs(r.suggestion) } }
            if bad.isEmpty {
                outcome.approved = true
                break
            }
            banned += bad.map(\.suggestion)
            outcome.rejected += bad
            outcome.suggestions.removeAll { s in bad.contains { $0.suggestion.sameAs(s) } }
            guard outcome.rounds < maxRounds else { break }

            progress(.revising(round: outcome.rounds))
            guard let revised = try? await proposer.revise(note: note, kept: outcome.suggestions, rejected: bad, now: now) else { continue }
            let again = Grounding.review(revised, note: note, now: now, calendar: calendar)
            outcome.rejected += again.rejected
            outcome.suggestions = again.kept.filter { s in !banned.contains { $0.sameAs(s) } }
        }
        return outcome
    }
}
