// Stand-ins for the two model sessions when the on-device model cannot
// run: a proposer that makes every mistake the first prompt made — and
// a few the rules cannot see — and a judge that applies the judge
// prompt's stated criteria by hand. Together they measure what the
// rules catch on their own and what the judge prompt has to say.

import Foundation
@testable import Tend

/// The old extractor's habits, applied to every note on purpose, each
/// draft tagged with the mistake it embodies. The second draft is the
/// heuristic's, as if the critique had landed.
final class EagerStandIn: SuggestionProposer {
    private(set) var modes: [UUID: String] = [:]
    private let calendar: Calendar
    init(calendar: Calendar) { self.calendar = calendar }

    private static let feeling = try! NSRegularExpression(pattern: "\\b(nervous|worried|tired|down|dreading|stressed|happy|excited|sad|lazy|fine|okay)\\b", options: .caseInsensitive)
    private static let someoneElse = try! NSRegularExpression(pattern: "\\b(her|his|their) (husband|wife|partner|mom|dad|brother|sister|son|daughter|kids?)\\b", options: .caseInsensitive)
    private static let employer = try! NSRegularExpression(pattern: "(?:at|for) ([A-Z][a-zA-Z]+)")
    private static let loves = try! NSRegularExpression(pattern: "\\bloves ([a-z]+)")
    private static let pastTense = try! NSRegularExpression(pattern: "\\b(ran|was|had|went|got back|did)\\b", options: .caseInsensitive)
    private static let hedge = try! NSRegularExpression(pattern: "\\b(might|maybe|at some point|sometime)\\b", options: .caseInsensitive)
    private static let ours = try! NSRegularExpression(pattern: "\\b(our|we'd|we said)\\b", options: .caseInsensitive)
    private static let meal = try! NSRegularExpression(pattern: "\\b(dinner|lunch|coffee|drinks)\\b", options: .caseInsensitive)
    private static let baby = try! NSRegularExpression(pattern: "\\bbaby\\b", options: .caseInsensitive)
    private static let eventWords: Set<String> = ["interview", "surgery", "wedding", "exam", "presentation", "trip", "marathon", "launch", "party", "biopsy", "offsite", "conference"]

    private func tag(_ s: Suggestion, _ mode: String) -> Suggestion {
        modes[s.id] = mode
        return s
    }

    private func match(_ re: NSRegularExpression, _ text: String) -> NSTextCheckingResult? {
        re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private func group(_ m: NSTextCheckingResult, _ i: Int, in text: String) -> String? {
        Range(m.range(at: i), in: text).map { String(text[$0]) }
    }

    func propose(note: String, now: Date) async throws -> [Suggestion] {
        let due = HeuristicExtractor.followUpDue(after: nil, now: now, calendar: calendar)
        var out = HeuristicExtractor(calendar: calendar).suggestions(for: note, now: now).map { tag($0, "heuristic") }
        let sentences = HeuristicExtractor.sentences(note)
        for sentence in sentences {
            let canonical = HeuristicExtractor.eventTitle(in: sentence)
            let dated = HeuristicExtractor.date(in: sentence, now: now, calendar: calendar) != nil
            if let m = match(Self.feeling, sentence), let word = group(m, 1, in: sentence) {
                out.append(tag(.followUp("Ask how she is feeling", due: due, because: sentence), "feelings"))
                out.append(tag(.fact("Mood", word), "feelings"))
            }
            if match(Self.someoneElse, sentence) != nil {
                if let m = match(Self.employer, sentence), let place = group(m, 1, in: sentence) {
                    out.append(tag(.fact("Works at", place), "someone-else"))
                }
                if let m = match(Self.loves, sentence), let thing = group(m, 1, in: sentence) {
                    out.append(tag(.fact("Likes", thing), "someone-else"))
                }
                if let word = HeuristicExtractor.words(sentence).first(where: { Self.eventWords.contains($0) }) {
                    out.append(tag(.fact("Family", word), "someone-else"))
                }
            }
            if match(HeuristicExtractor.aboutSelf, sentence) != nil, let canonical {
                let day = HeuristicExtractor.date(in: sentence, now: now, calendar: calendar)
                out.append(tag(.followUp(canonical, due: HeuristicExtractor.followUpDue(after: day, now: now, calendar: calendar), because: sentence), "writer-self"))
            }
            if let canonical, !dated, match(Self.pastTense, sentence) != nil {
                out.append(tag(.followUp(canonical, due: due, because: sentence), "stale"))
            }
            if let canonical, !dated, match(Self.hedge, sentence) != nil {
                out.append(tag(.followUp(canonical, due: due, because: sentence), "hedged"))
            }
            if match(Self.ours, sentence) != nil, match(Self.meal, sentence) != nil {
                let day = HeuristicExtractor.date(in: sentence, now: now, calendar: calendar)
                out.append(tag(.followUp("Confirm the dinner", due: HeuristicExtractor.followUpDue(after: day, now: now, calendar: calendar), because: sentence), "writer-plan"))
            }
            if match(Self.baby, sentence) != nil, !dated {
                out.append(tag(.followUp("Check in about the baby", due: due, because: sentence), "possession"))
            }
            if let canonical {
                if let word = HeuristicExtractor.words(sentence).first(where: { Self.eventWords.contains($0) }) {
                    out.append(tag(.fact(word.capitalized, sentence.split(separator: " ").prefix(3).joined(separator: " ")), "event-as-fact"))
                }
                out.append(tag(.followUp(canonical, due: due, because: "They have something coming up soon that matters to them."), "paraphrase"))
            }
        }
        if let first = sentences.first {
            out.append(tag(.followUp("Check in", due: due, because: first), "generic"))
        }
        out.append(tag(.fact("Kids", "none"), "placeholder"))
        out.append(tag(.fact("Partner", "unknown"), "placeholder"))
        return out
    }

    func revise(note: String, kept: [Suggestion], rejected: [Rejection], now: Date) async throws -> [Suggestion] {
        HeuristicExtractor(calendar: calendar).suggestions(for: note, now: now).map { tag($0, "heuristic") }
    }
}

/// The judge prompt's criteria, applied by hand: a fact about someone
/// else in the note, and a plan that includes the note-writer.
struct StandInJudge: SuggestionJudge {
    private static let someoneElse = try! NSRegularExpression(pattern: "\\b(her|his|their) (husband|wife|partner|mom|dad|brother|sister|son|daughter|kids?)\\b", options: .caseInsensitive)
    private static let ours = try! NSRegularExpression(pattern: "\\b(our|we'd|we said|we should|let's)\\b", options: .caseInsensitive)
    private static let relationship: Set<String> = ["partner", "kids", "pets", "husband", "wife", "children"]

    func review(note: String, proposals: [Suggestion], now: Date) async throws -> [Rejection] {
        let aboutOthers = HeuristicExtractor.sentences(note).filter {
            Self.someoneElse.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil
        }
        return proposals.compactMap { s in
            if s.isFollowUp {
                if Self.ours.firstMatch(in: s.detail, range: NSRange(s.detail.startIndex..., in: s.detail)) != nil {
                    return Rejection(suggestion: s, reason: "a plan that includes the note-writer")
                }
                return nil
            }
            guard !Self.relationship.contains(s.title.lowercased()) else { return nil }
            let valueWords = Set(HeuristicExtractor.words(s.detail))
            let inOthers = aboutOthers.contains { sentence in
                !valueWords.isDisjoint(with: Set(HeuristicExtractor.words(sentence)))
            }
            return inOthers ? Rejection(suggestion: s, reason: "a fact about someone else in the note") : nil
        }
    }
}
