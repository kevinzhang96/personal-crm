// The rules every proposal must pass before the reader sees it, whoever
// made it — the model or the heuristic. A proposal is kept only when the
// note itself says what it claims, and repaired where the note settles a
// detail (the day) better than the proposer did. Leaving one out costs
// nothing; showing an invented one costs trust.

import Foundation

/// A proposal set aside, and why — the critique a reviser is handed, and
/// what the tests read.
struct Rejection: Equatable {
    let suggestion: Suggestion
    let reason: String
}

enum Grounding {
    struct Review: Equatable {
        var kept: [Suggestion]
        var rejected: [Rejection]
    }

    /// What survives, deduplicated, and what fell.
    static func review(_ proposals: [Suggestion], note: String, now: Date, calendar: Calendar = .current) -> Review {
        var review = Review(kept: [], rejected: [])
        let noteWords = Set(words(note))
        for proposal in proposals {
            switch vet(proposal, note: note, noteWords: noteWords, now: now, calendar: calendar) {
            case .keep(let kept):
                if review.kept.contains(where: { $0.sameAs(kept) }) {
                    review.rejected.append(Rejection(suggestion: proposal, reason: "a repeat of another proposal"))
                } else {
                    review.kept.append(kept)
                }
            case .drop(let reason):
                review.rejected.append(Rejection(suggestion: proposal, reason: reason))
            }
        }
        return review
    }

    enum Verdict: Equatable {
        case keep(Suggestion)
        case drop(String)
    }

    static func vet(_ s: Suggestion, note: String, now: Date, calendar: Calendar = .current) -> Verdict {
        vet(s, note: note, noteWords: Set(words(note)), now: now, calendar: calendar)
    }

    private static func vet(_ s: Suggestion, note: String, noteWords: Set<String>, now: Date, calendar: Calendar) -> Verdict {
        s.isFollowUp
            ? vetFollowUp(s, note: note, noteWords: noteWords, now: now, calendar: calendar)
            : vetFact(s, noteWords: noteWords)
    }

    // MARK: follow-ups

    private static func vetFollowUp(_ s: Suggestion, note: String, noteWords: Set<String>, now: Date, calendar: Calendar) -> Verdict {
        let evidence = s.detail
        guard grounded(evidence, in: note) else { return .drop("the evidence sentence isn't in the note") }
        let canonical = HeuristicExtractor.eventTitle(in: evidence)
        let sentenceDay = HeuristicExtractor.date(in: evidence, now: now, calendar: calendar)
        guard canonical != nil || sentenceDay != nil else { return .drop("the sentence names no event and no day") }
        if let sentenceDay, Dates.daysBetween(sentenceDay, now, calendar: calendar) > 3 {
            return .drop("the event is already past")
        }

        // The sentence's own day, resolved here, beats the proposer's
        // arithmetic; without one the proposer's day stands if it is ahead.
        let due: Date
        if let sentenceDay {
            due = HeuristicExtractor.followUpDue(after: sentenceDay, now: now, calendar: calendar)
        } else if let proposed = s.dueDate, proposed >= calendar.startOfDay(for: now) {
            due = proposed
        } else {
            return .drop("the day to follow up has passed")
        }

        guard let title = vetTitle(s.title, canonical: canonical, noteWords: noteWords) else {
            return .drop("the wording doesn't come from the note")
        }
        return .keep(Suggestion(id: s.id, kind: .followUp(due: due), title: title, detail: evidence))
    }

    /// The wording, made of the note's words and asking-words — or the
    /// canonical line for the event when the proposer's wording strays
    /// but the sentence is sound. Nil when it says nothing the note says.
    private static func vetTitle(_ title: String, canonical: String?, noteWords: Set<String>) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isReal(trimmed), trimmed.count <= 120 else { return canonical }
        if let canonical, normalized(trimmed) == normalized(canonical) { return canonical }
        let content = words(trimmed).filter { !glue.contains($0) }
        let ungrounded = content.filter { !inNote($0, noteWords) }
        let inferred = ungrounded.filter { inference.contains($0) }
        let grounded = content.count - ungrounded.count
        if inferred.isEmpty, ungrounded.count <= 1, grounded >= 1 { return trimmed }
        return canonical
    }

    // MARK: facts

    private static func vetFact(_ s: Suggestion, noteWords: Set<String>) -> Verdict {
        let label = s.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = s.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isReal(label), label.count <= 30 else { return .drop("the label is blank or too long") }
        guard !words(label).contains(where: { notAFact.contains($0) }) else {
            return .drop("a mood, plan or opinion is a guess, not a fact")
        }
        guard isReal(value) else { return .drop("the value is a placeholder") }
        guard value.count <= 100, words(value).count <= 8 else { return .drop("the value is a passage, not a detail") }
        guard normalized(value) != normalized(label) else { return .drop("the value repeats the label") }
        let strayed = words(value).filter { !stopwords.contains($0) && !inNote($0, noteWords) }
        guard strayed.isEmpty else { return .drop("uses words the note doesn't: \(strayed.joined(separator: ", "))") }
        return .keep(Suggestion(id: s.id, kind: .fact, title: label, detail: value))
    }

    // MARK: words

    /// The evidence was quoted, not composed: it appears in the note as
    /// written, or nearly — at least three content words with almost all
    /// of them the note's own.
    static func grounded(_ evidence: String, in note: String) -> Bool {
        let evidenceWords = words(evidence)
        let content = evidenceWords.filter { $0.count >= 3 }
        guard content.count >= 2 else { return false }
        if (" " + normalized(note) + " ").contains(" " + evidenceWords.joined(separator: " ") + " ") { return true }
        let noteWords = Set(words(note))
        let hits = content.filter { noteWords.contains($0) }.count
        return content.count >= 3 && hits * 100 >= content.count * 85
    }

    /// Small models fill every slot they were told about; a slot filled
    /// with a word for "nothing" is nothing.
    static func isReal(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?-—\"'"))
        guard !v.isEmpty else { return false }
        if placeholders.contains(v) { return false }
        return !["not mentioned", "not specified", "not stated", "unknown", "no information", "doesn't say", "does not say", "n/a"]
            .contains { v.contains($0) }
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    static func normalized(_ text: String) -> String { words(text).joined(separator: " ") }

    /// A note word, allowing an inflection either way once the word is
    /// long enough for a prefix to mean something.
    static func inNote(_ word: String, _ noteWords: Set<String>) -> Bool {
        if noteWords.contains(word) { return true }
        guard word.count >= 4 else { return false }
        return noteWords.contains { $0.count >= 4 && ($0.hasPrefix(word) || word.hasPrefix($0)) }
    }

    private static let placeholders: Set<String> = [
        "none", "n/a", "na", "nil", "null", "unknown", "unspecified", "not specified", "not mentioned", "not given",
        "not stated", "no", "nothing", "tbd", "?", "-", "…", "...", "empty", "blank", "unclear",
    ]

    /// Labels that name a reading of the friend rather than a fact about
    /// them, or that are a follow-up in a fact's clothing.
    private static let notAFact: Set<String> = [
        "feeling", "feelings", "mood", "emotion", "emotions", "opinion", "opinions", "thought", "thoughts", "personality",
        "attitude", "sentiment", "stress", "worry", "worries", "concern", "concerns", "plan", "plans", "intention",
        "intentions", "goal", "goals", "status", "summary", "note", "notes", "reminder", "event", "events", "todo",
        "follow", "followup", "update", "activity", "activities", "topic", "topics", "discussion", "conversation",
    ]

    /// Title words that read something into the friend the note may not
    /// have said; allowed only when the note itself uses them.
    private static let inference: Set<String> = [
        "feel", "feels", "feeling", "feelings", "felt", "cope", "coping", "stress", "stressed", "anxious", "anxiety",
        "nervous", "worried", "worry", "worries", "happy", "excited", "sad", "upset", "mood", "emotion", "emotions",
        "plan", "plans", "planning", "decide", "decision", "thinking", "consider", "considering", "hope", "hoping",
        "expect", "expecting", "opinion", "thoughts", "enjoy", "enjoying", "enjoyed", "reason", "reasons", "why",
    ]

    /// The words a follow-up is allowed to add to the note's own: the
    /// asking, not the subject.
    private static let glue: Set<String> = [
        "ask", "asked", "asking", "check", "checking", "see", "find", "out", "whether", "if", "how", "went", "did", "is",
        "was", "were", "are", "be", "been", "about", "after", "before", "on", "in", "at", "of", "the", "a", "an", "to",
        "for", "with", "and", "or", "her", "his", "their", "them", "they", "she", "he", "it", "its", "this", "that",
        "up", "follow", "wish", "luck", "good", "congratulate", "congratulations", "hear", "heard", "gone", "go",
        "going", "get", "got", "doing", "done", "do", "does", "turned", "what", "who", "when", "where", "any", "news",
        "update", "updates", "result", "results", "recovering", "recovery", "back", "home", "well", "okay", "ok",
        "still", "yet", "now", "later", "today", "tomorrow", "week", "next", "since", "much", "more", "everything",
        "things", "thing", "time", "day", "days", "again", "soon", "there", "over", "through", "from", "into", "off",
        "one", "some", "all", "s", "t", "re", "ve", "ll", "d", "m", "has", "have", "had", "will", "would", "could",
        "should", "can", "let", "know", "make", "sure", "message", "text", "call", "send", "say", "tell", "share",
    ]

    private static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "of", "at", "in", "on", "to", "with", "for", "from", "by", "her", "his", "their",
        "its", "is", "are", "was", "were", "be", "s", "t", "re", "ve", "ll", "d", "m", "as", "that", "this", "it",
        "he", "she", "they", "them", "him", "we", "i", "you", "my", "our", "your", "but", "so", "if", "not", "also",
        "just", "very", "really", "quite", "some", "any", "all", "has", "have", "had", "who", "which", "named", "called",
    ]
}
