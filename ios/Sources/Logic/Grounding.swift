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
                // Two follow-ups on the same occasion are one, however
                // differently they are worded.
                let occasion = kept.isFollowUp ? HeuristicExtractor.eventTitle(in: kept.detail) : nil
                let repeated = review.kept.contains { $0.sameAs(kept) }
                    || (occasion != nil && review.kept.contains { $0.isFollowUp && HeuristicExtractor.eventTitle(in: $0.detail) == occasion })
                if repeated {
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
            : vetFact(s, note: note, noteWords: noteWords, now: now, calendar: calendar)
    }

    // MARK: follow-ups

    private static func vetFollowUp(_ s: Suggestion, note: String, noteWords: Set<String>, now: Date, calendar: Calendar) -> Verdict {
        let evidence = s.detail
        guard grounded(evidence, in: note) else { return .drop("the evidence sentence isn't in the note") }
        let range = NSRange(evidence.startIndex..., in: evidence)
        guard HeuristicExtractor.aboutSelf.firstMatch(in: evidence, range: range) == nil else {
            return .drop("the sentence is about the note-writer")
        }
        let canonical = HeuristicExtractor.eventTitle(in: evidence)
        let sentenceDay = HeuristicExtractor.date(in: evidence, now: now, calendar: calendar)
        guard canonical != nil || sentenceDay != nil else { return .drop("the sentence names no event and no day") }
        if let sentenceDay, Dates.daysBetween(sentenceDay, now, calendar: calendar) > 3 {
            return .drop("the event is already past")
        }
        if bygoneYear.firstMatch(in: evidence, range: range).flatMap({ Range($0.range, in: evidence) })
            .flatMap({ Int(evidence[$0]) }).map({ $0 < calendar.component(.year, from: now) }) == true {
            return .drop("the event is already past")
        }
        if sentenceDay == nil, hedge.firstMatch(in: evidence, range: range) != nil {
            return .drop("the note only wonders about it")
        }
        // A day alone is not an occasion when the note-writer is in the
        // sentence: "we watched the match on Saturday" is their weekend.
        if canonical == nil, firstPerson.firstMatch(in: evidence, range: range) != nil {
            return .drop("the note-writer is part of it")
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

        guard let title = vetTitle(s.title, canonical: canonical, noteWords: noteWords, evidence: evidence) else {
            return .drop("the wording doesn't come from the note")
        }
        return .keep(Suggestion(id: s.id, kind: .followUp(due: due), title: title, detail: evidence))
    }

    /// The wording, made of the note's words and asking-words — or the
    /// canonical line for the event when the proposer's wording strays
    /// but the sentence is sound: a question put to the friend, the
    /// sentence said back, a feeling read in. Nil when it says nothing
    /// the note says.
    private static func vetTitle(_ title: String, canonical: String?, noteWords: Set<String>, evidence: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isReal(trimmed), trimmed.count <= 120 else { return canonical }
        if let canonical, normalized(trimmed) == normalized(canonical) { return canonical }
        if trimmed.hasSuffix("?") || question.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil { return canonical }
        if restates(trimmed, evidence) { return canonical }
        let content = words(trimmed).filter { !glue.contains($0) }
        let ungrounded = content.filter { !inNote($0, noteWords) }
        let inferred = ungrounded.filter { inference.contains($0) }
        let grounded = content.count - ungrounded.count
        if inferred.isEmpty, ungrounded.count <= 1, grounded >= 1 { return trimmed }
        return canonical
    }

    // MARK: facts

    private static func vetFact(_ s: Suggestion, note: String, noteWords: Set<String>, now: Date, calendar: Calendar) -> Verdict {
        let label = s.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = s.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isReal(label), label.count <= 30 else { return .drop("the label is blank or too long") }
        guard !words(label).contains(where: { notAFact.contains($0) }) else {
            return .drop("a mood, plan or opinion is a guess, not a fact")
        }
        guard HeuristicExtractor.eventTitle(in: label) == nil else { return .drop("an event is not a fact") }
        guard let kind = knownLabel(label) else { return .drop("not a kind of detail worth keeping") }
        guard isReal(value), !words(value).contains(where: { placeholders.contains($0) }) else { return .drop("the value is a placeholder") }
        guard value.count <= 100, words(value).count <= 8 else { return .drop("the value is a passage, not a detail") }
        guard normalized(value) != normalized(label) else { return .drop("the value repeats the label") }
        guard !words(value).contains(where: { clause.contains($0) }), !value.hasSuffix(".") else {
            return .drop("the value is a phrase from the note, not a name, place or thing")
        }
        guard HeuristicExtractor.eventTitle(in: value) == nil else { return .drop("an event is not a fact") }
        guard !words(value).allSatisfy({ generic.contains($0) || stopwords.contains($0) }) else {
            return .drop("the value names nothing in particular")
        }
        let strayed = words(value).filter { !stopwords.contains($0) && !inNote($0, noteWords) }
        guard strayed.isEmpty else { return .drop("uses words the note doesn't: \(strayed.joined(separator: ", "))") }
        guard HeuristicExtractor.date(in: value, now: now, calendar: calendar) == nil,
              timePhrase.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) == nil
        else { return .drop("a time, not a detail") }

        // The sentences the value lives in decide whose detail it is and
        // what kind: "interview at Figma" is not an employer, "got back
        // from Peru" is not a home, and a husband's start date is his.
        let content = words(value).filter { !stopwords.contains($0) }
        let sentences = HeuristicExtractor.sentences(note).filter { sentence in
            let sentenceWords = Set(words(sentence))
            return content.contains { inNote($0, sentenceWords) }
        }
        if !relationshipLabels.contains(kind), !sentences.isEmpty,
           sentences.allSatisfy({ aboutSomeoneElse($0, value: content) }) {
            return .drop("a detail about someone else in the note")
        }
        if let cue = labelCues[kind] {
            let said = sentences.contains { near(cue, value: content, in: $0) }
                || cue.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
            guard said else { return .drop("the note doesn't say that about them") }
        }
        // A partner, a child, a pet, an employer, a town: the note writes
        // a name with a capital. "two dogs" and "redesign" are not names.
        if namedLabels.contains(kind), let first = value.split(separator: " ").first.map(String.init),
           !note.contains(first.prefix(1).uppercased() + first.dropFirst()) {
            return .drop("a name is expected here, and the note gives none")
        }
        return .keep(Suggestion(id: s.id, kind: .fact, title: kind, detail: value))
    }

    /// The kinds of detail Tend keeps, and the words a model uses for
    /// them. A label outside this is a slot the model invented.
    static let labels = ["Partner", "Kids", "Works at", "Role", "Lives in", "Hometown", "Likes", "Dislikes", "Gift idea",
                         "Working on", "Allergy", "Pets", "Met through"]

    static func knownLabel(_ label: String) -> String? {
        let key = normalized(label)
        if let exact = labels.first(where: { normalized($0) == key }) { return exact }
        return synonyms[key]
    }

    private static let synonyms: [String: String] = [
        "spouse": "Partner", "husband": "Partner", "wife": "Partner", "girlfriend": "Partner", "boyfriend": "Partner",
        "fiance": "Partner", "fiancee": "Partner", "significant other": "Partner",
        "children": "Kids", "child": "Kids", "kid": "Kids", "daughter": "Kids", "son": "Kids", "kids names": "Kids",
        "kid s names": "Kids", "children s names": "Kids",
        "job": "Works at", "work": "Works at", "employer": "Works at", "company": "Works at", "employment": "Works at",
        "workplace": "Works at", "occupation": "Role", "title": "Role", "position": "Role", "profession": "Role",
        "city": "Lives in", "location": "Lives in", "lives": "Lives in", "home": "Lives in", "residence": "Lives in",
        "address": "Lives in", "where they live": "Lives in", "where she lives": "Lives in", "where he lives": "Lives in",
        "hobby": "Likes", "hobbies": "Likes", "interest": "Likes", "interests": "Likes", "like": "Likes", "loves": "Likes",
        "favorite": "Likes", "favourite": "Likes", "enjoys": "Likes",
        "dislike": "Dislikes", "hates": "Dislikes",
        "gift": "Gift idea", "gift ideas": "Gift idea", "wants": "Gift idea", "wishlist": "Gift idea", "wish list": "Gift idea",
        "project": "Working on", "projects": "Working on",
        "allergies": "Allergy", "allergic": "Allergy", "allergic to": "Allergy",
        "pet": "Pets", "dog": "Pets", "cat": "Pets", "puppy": "Pets",
        "met": "Met through", "how we met": "Met through",
    ]

    /// The value follows a relative in the same clause: "her husband
    /// Marco just started at Anthropic" is about him; "she's at Figma and
    /// her kids are called Lu" is still about her.
    private static func aboutSomeoneElse(_ sentence: String, value: [String]) -> Bool {
        let lower = sentence.lowercased()
        guard let relative = HeuristicExtractor.someoneElse.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)),
              let relativeRange = Range(relative.range, in: sentence)
        else { return false }
        let from = lower.index(lower.startIndex, offsetBy: sentence.distance(from: sentence.startIndex, to: relativeRange.upperBound))
        let after = lower[from...]
        guard let hit = value.compactMap({ after.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else { return false }
        let between = after[..<hit.lowerBound]
        return !between.contains(",") && !between.contains(";")
    }

    /// The cue and the value within a few words of each other: "for like
    /// an hour … dinner" is not a liking.
    private static func near(_ cue: NSRegularExpression, value: [String], in sentence: String) -> Bool {
        let tokens = words(sentence)
        let valueAt = tokens.indices.filter { i in value.contains { inNote($0, [tokens[i]]) } }
        guard !valueAt.isEmpty else { return false }
        return tokens.indices.contains { i in
            cue.firstMatch(in: tokens[i], range: NSRange(tokens[i].startIndex..., in: tokens[i])) != nil
                && valueAt.contains { abs($0 - i) <= 6 }
        }
    }

    /// The kinds whose value is a proper name.
    private static let namedLabels: Set<String> = ["Partner", "Kids", "Pets", "Works at", "Lives in", "Hometown"]

    /// The labels whose value is the relationship itself, which a
    /// sentence about that person states.
    private static let relationshipLabels: Set<String> = ["Partner", "Kids", "Pets"]

    /// A value that is a when, not a what.
    private static let timePhrase = try! NSRegularExpression(
        pattern: "\\b(next|last|this|every) (week|month|year|spring|summer|autumn|fall|winter|weekend|morning|evening)\\b|\\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|tomorrow|yesterday|today|tonight)\\b|\\b\\d{4}-\\d{2}-\\d{2}\\b",
        options: .caseInsensitive)

    /// For each kind of detail, the words a note uses when it states one;
    /// a value with none of them nearby is a slot filled, not a fact.
    private static let labelCues: [String: NSRegularExpression] = [
        "Partner": "\\b(husband|wife|partner|boyfriend|girlfriend|fianc[ée]e?|spouse|married|marrying|dating|engaged)\\b",
        "Kids": "\\b(sons?|daughters?|kids?|child|children|baby|twins|born|toddler|teenagers?)\\b",
        "Works at": "\\b(works?|working|job|started|starting|starts|joined|joining|employ\\w*|hired|company|role|intern\\w*|firm|startup|engineer|designer|manager|director|teacher|nurse|doctor|lawyer|founder|developer|analyst|consultant|accountant|researcher|scientist|editor|writer)\\b",
        "Role": "\\b(as an?|role|title|position|promoted|works as|now an?|engineer|designer|manager|director|teacher|nurse|doctor|lawyer|founder)\\b",
        "Lives in": "\\b(lives?|living|moved|moving|based|relocat\\w*|home|settled|staying|apartment|house|neighbou?rhood|now in)\\b",
        "Hometown": "\\b(from|grew up|hometown|born|raised)\\b",
        "Likes": "\\b(likes?|loves?|into|fan|enjoys?|hobby|hobbies|favou?rite|obsessed|keen|adores?)\\b",
        "Dislikes": "\\b(hates?|dislikes?|can't stand|not a fan|avoids?)\\b",
        "Gift idea": "\\b(wants?|wanting|would love|eyeing|wish|gift|asked for|looking for|needs?)\\b",
        "Working on": "\\b(working on|building|project|writing|launching|side project)\\b",
        "Allergy": "\\b(allerg\\w*|intoleran\\w*|can't eat|cannot eat)\\b",
        "Pets": "\\b(dog|cat|puppy|kitten|pet|rabbit|parrot|hamster|adopted|rescued)\\b",
        "Met through": "\\b(met|introduced|through|via)\\b",
    ].mapValues { try! NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    /// A follow-up worded as a question to the friend rather than a
    /// note to the reader.
    private static let question = try! NSRegularExpression(
        pattern: "^(when|what|what's|whats|did|do|does|can|could|would|will|how|is|are|was|were|have|has|who|where|why|tell me|is there)\\b",
        options: .caseInsensitive)

    // MARK: words

    /// The title is the sentence again, more or less.
    private static func restates(_ title: String, _ evidence: String) -> Bool {
        let t = Set(words(title)), e = Set(words(evidence))
        guard e.count >= 5 else { return normalized(title) == normalized(evidence) }
        return t.intersection(e).count * 10 >= e.count * 8
    }

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

    /// A year before this one, in a sentence: what it describes has happened.
    private static let bygoneYear = try! NSRegularExpression(pattern: "\\b(19|20)\\d\\d\\b")

    /// An event the note only floats; without a day it is not something
    /// to ask about afterwards.
    private static let hedge = try! NSRegularExpression(
        pattern: "\\b(might|maybe|perhaps|possibly|at some point|sometime|someday|one day|thinking about|thinking of|considering|hopefully|if (she|he|they) can|no plans?)\\b",
        options: .caseInsensitive)

    /// The note-writer, in a sentence.
    private static let firstPerson = try! NSRegularExpression(
        pattern: "\\b(I|I'm|I’m|I've|I’ve|we|we're|we’re|we'll|we’ll|we'd|we’d|our|us|my)\\b", options: .caseInsensitive)

    /// Words that make a value a clause rather than a name, place or thing.
    private static let clause: Set<String> = [
        "she", "he", "they", "her", "his", "their", "you", "your", "i", "we", "it", "is", "are", "was", "were", "be",
        "been", "being", "am", "has", "have", "had", "do", "does", "did", "will", "would", "can", "could", "should",
        "s", "re", "ve", "ll", "d", "m", "t", "not", "isn", "don", "doesn", "didn", "won", "just", "really", "so",
    ]

    /// Nouns that name nothing in particular: a value made only of these
    /// is the shape of a fact without one.
    private static let generic: Set<String> = [
        "company", "town", "city", "place", "work", "job", "home", "house", "office", "school", "board", "team",
        "people", "someone", "somebody", "thing", "things", "stuff", "everything", "anything", "something", "area",
        "spot", "there", "here", "somewhere", "elsewhere", "family", "friend", "friends", "partner", "kids", "kid",
        "child", "children", "pet", "pets", "name", "names",
    ]

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
