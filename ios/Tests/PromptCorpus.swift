// The notes the extractor is measured against: what a reader actually
// writes after a call, labelled with what should come out — most often
// nothing. Scoring favours omission: a proposal nobody asked for is a
// false positive, a missed one a false negative, and a few reasonable
// readings are tolerated either way.

import Foundation
@testable import Tend

struct CorpusCase {
    enum Expectation: Equatable {
        /// A follow-up whose title or evidence mentions any of these.
        case followUp([String])
        /// A fact whose label contains one of the keys and whose value contains the text.
        case fact(labels: [String], value: String)

        func matches(_ s: Suggestion) -> Bool {
            switch self {
            case .followUp(let words):
                guard s.isFollowUp else { return false }
                let text = (s.title + " " + s.detail).lowercased()
                return words.contains { text.contains($0) }
            case .fact(let labels, let value):
                guard !s.isFollowUp else { return false }
                let label = s.title.lowercased()
                return labels.contains { label.contains($0) } && s.detail.lowercased().contains(value.lowercased())
            }
        }

        var short: String {
            switch self {
            case .followUp(let words): "follow-up(\(words[0]))"
            case .fact(let labels, let value): "fact(\(labels[0]): \(value))"
            }
        }
    }

    let id: String
    let note: String
    /// What must come out.
    var expected: [Expectation] = []
    /// What may come out without penalty.
    var tolerated: [Expectation] = []
    /// Expectations the pattern-matching path is not expected to find.
    var modelOnly: [Expectation] = []

    var shouldBeEmpty: Bool { expected.isEmpty }
}

/// One case scored: what matched, what was extra, what was missed.
struct CaseScore {
    let id: String
    var truePositives: [Suggestion] = []
    var falsePositives: [Suggestion] = []
    var falseNegatives: [CorpusCase.Expectation] = []
    var toleratedHits: [Suggestion] = []

    static func score(_ kept: [Suggestion], against c: CorpusCase) -> CaseScore {
        var score = CaseScore(id: c.id)
        var open = c.expected
        for s in kept {
            if let i = open.firstIndex(where: { $0.matches(s) }) {
                open.remove(at: i)
                score.truePositives.append(s)
            } else if c.tolerated.contains(where: { $0.matches(s) }) {
                score.toleratedHits.append(s)
            } else {
                score.falsePositives.append(s)
            }
        }
        score.falseNegatives = open
        return score
    }
}

struct CorpusMetrics: CustomStringConvertible {
    var tp = 0, fp = 0, fn = 0
    var emptyCases = 0, cleanEmptyCases = 0
    var casesWithFalsePositives: [String] = []
    var casesWithFalseNegatives: [String] = []

    init(_ scores: [CaseScore], corpus: [CorpusCase]) {
        for s in scores {
            tp += s.truePositives.count
            fp += s.falsePositives.count
            fn += s.falseNegatives.count
            if !s.falsePositives.isEmpty { casesWithFalsePositives.append(s.id) }
            if !s.falseNegatives.isEmpty { casesWithFalseNegatives.append(s.id) }
            if let c = corpus.first(where: { $0.id == s.id }), c.shouldBeEmpty {
                emptyCases += 1
                if s.falsePositives.isEmpty { cleanEmptyCases += 1 }
            }
        }
    }

    var precision: Double { tp + fp == 0 ? 1 : Double(tp) / Double(tp + fp) }
    var recall: Double { tp + fn == 0 ? 1 : Double(tp) / Double(tp + fn) }

    var description: String {
        String(format: "precision %.2f (tp %d, fp %d) · recall %.2f (fn %d) · clean empties %d/%d",
               precision, tp, fp, recall, fn, cleanEmptyCases, emptyCases)
    }
}

enum PromptCorpus {
    /// Saturday 2026-09-05, 15:00 — relative phrases in the notes resolve
    /// against this, so nothing here names an absolute date.
    static let calendar = Calendar(identifier: .gregorian)
    static var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 15))! }

    static let cases: [CorpusCase] = [
        // MARK: clear events and facts
        CorpusCase(id: "interview-next-week",
                   note: "Priya said her interview at Figma is next Thursday and she's nervous about the system design round.",
                   expected: [.followUp(["interview"])]),
        CorpusCase(id: "surgery-thursday",
                   note: "Sam has knee surgery on Thursday. He'll be off his feet for a couple of weeks after.",
                   expected: [.followUp(["surgery"])]),
        CorpusCase(id: "partner-move-kid",
                   note: "Her husband Marco just started at Anthropic. They moved to Oakland last month. Their daughter is called Lu.",
                   expected: [.fact(labels: ["partner", "husband", "spouse"], value: "Marco"),
                              .fact(labels: ["live", "city", "location", "home"], value: "Oakland"),
                              .fact(labels: ["kid", "child", "daughter"], value: "Lu")]),
        CorpusCase(id: "gift-pet-allergy",
                   note: "He's been wanting a pour-over kettle for ages. They got a puppy named Biscuit last week. Oh and he's allergic to shellfish.",
                   expected: [.fact(labels: ["gift", "want", "wish"], value: "kettle"),
                              .fact(labels: ["pet", "dog", "puppy"], value: "Biscuit"),
                              .fact(labels: ["allerg"], value: "shellfish")]),
        CorpusCase(id: "trip-lisbon",
                   note: "She's flying to Lisbon next Saturday for two weeks.",
                   expected: [.followUp(["lisbon", "trip", "flight", "flying"])]),
        CorpusCase(id: "wedding-three-weeks",
                   note: "The wedding is in three weeks, small ceremony at her parents' place.",
                   expected: [.followUp(["wedding"])]),
        CorpusCase(id: "marathon-soon",
                   note: "She's going to run her first marathon soon, training four days a week.",
                   expected: [.followUp(["marathon", "race"])],
                   tolerated: [.fact(labels: ["like", "hobb", "interest", "sport"], value: "")]),
        CorpusCase(id: "exam-tomorrow",
                   note: "Big bar exam tomorrow. She's been studying nonstop.",
                   expected: [.followUp(["exam"])]),
        CorpusCase(id: "move-couple-days",
                   note: "They're moving into the new place in a couple of days, boxes everywhere.",
                   expected: [.followUp(["move", "moving", "new place"])]),
        CorpusCase(id: "new-job-monday",
                   note: "Dev starts his new job at Stripe on Monday, first day nerves.",
                   expected: [.followUp(["job", "first day", "stripe"]),
                              .fact(labels: ["work", "employer", "job", "company"], value: "Stripe")]),
        CorpusCase(id: "baby-due",
                   note: "Their baby is due next month; they've picked the name Noor.",
                   expected: [.followUp(["baby", "due"])],
                   tolerated: [.fact(labels: ["kid", "child", "baby", "name"], value: "Noor"),
                               .fact(labels: ["kid", "child", "baby"], value: "baby")]),
        CorpusCase(id: "multi-event",
                   note: "Her presentation to the board is on Tuesday, and then she flies to Tokyo on Friday for the offsite.",
                   expected: [.followUp(["presentation", "board"]), .followUp(["tokyo", "offsite", "trip", "conference"])],
                   // One sentence, two events: pattern matching takes the first event word per sentence.
                   modelOnly: [.followUp(["tokyo", "offsite", "trip", "conference"])]),
        CorpusCase(id: "lives-works",
                   note: "Caught up over coffee. She lives in Long Island City now and works at Spotify as a designer.",
                   expected: [.fact(labels: ["live", "city", "location", "home"], value: "Long Island City"),
                              .fact(labels: ["work", "employer", "company"], value: "Spotify")],
                   tolerated: [.fact(labels: ["role", "job", "title", "work"], value: "designer")]),
        CorpusCase(id: "birthday-party",
                   note: "Her birthday party is on Saturday at that rooftop bar; she said not to bring gifts.",
                   expected: [.followUp(["party", "birthday"])],
                   tolerated: [.fact(labels: ["birthday", "date"], value: "")]),
        CorpusCase(id: "two-people",
                   note: "Dinner with Maya and Tom. Tom's startup is launching next month; Maya just got back from Peru.",
                   expected: [.followUp(["launch"])],
                   tolerated: [.fact(labels: ["work", "startup", "company"], value: "")]),
        CorpusCase(id: "mom-biopsy",
                   note: "Her mom's biopsy results come back Wednesday; she's trying not to think about it.",
                   expected: [.followUp(["biopsy", "mom", "results", "appointment"])]),

        // MARK: nothing to extract — the common case
        CorpusCase(id: "plain-coffee", note: "We had coffee and caught up about work. Nice to see him."),
        CorpusCase(id: "feelings-only",
                   note: "She sounded really tired and a bit down about everything. Told her I'm here if she needs anything."),
        CorpusCase(id: "unstated-plans", note: "He mentioned he might look for a new job at some point, nothing concrete."),
        CorpusCase(id: "about-self", note: "I have an interview on Monday and asked him for tips. He was super helpful."),
        CorpusCase(id: "stale-event", note: "We talked about the marathon she ran in 2019 and how she's been lazy since."),
        CorpusCase(id: "last-week-surgery", note: "Her surgery was last Monday and she's recovering well."),
        CorpusCase(id: "possession-trap",
                   note: "She has a baby and two dogs, so the house is chaos.",
                   tolerated: [.fact(labels: ["pet", "dog"], value: "dog"), .fact(labels: ["kid", "child", "baby"], value: "")]),
        CorpusCase(id: "match-watching", note: "We watched the match on Saturday and ordered too much pizza."),
        CorpusCase(id: "working-with",
                   note: "She's working with Sarah on the redesign and it's going slowly.",
                   tolerated: [.fact(labels: ["working on", "project"], value: "redesign")]),
        CorpusCase(id: "would-love", note: "She would love to see you when she's next in town."),
        CorpusCase(id: "brothers-wedding",
                   note: "Talked about his brother's wedding next spring — he's the best man and stressed about the speech.",
                   tolerated: [.followUp(["wedding", "speech"]), .fact(labels: ["sibling", "brother", "family"], value: "")]),
        CorpusCase(id: "hearing-about", note: "He's been hearing about layoffs at his company and is worried."),
        CorpusCase(id: "performance-review",
                   note: "Her performance review is next week and she thinks it'll go fine.",
                   tolerated: [.followUp(["review"])]),
        CorpusCase(id: "our-dinner", note: "Rescheduled our dinner to next Friday because her sitter cancelled."),
        CorpusCase(id: "kid-name-trap",
                   note: "Her son is Tall for his age and loves dinosaurs.",
                   tolerated: [.fact(labels: ["kid", "child", "son"], value: "")]),
        CorpusCase(id: "transcript",
                   note: "um so yeah we talked for like an hour, she's doing okay, work is busy, um her mom is visiting next weekend which she's kind of dreading, and uh we said we'd do dinner sometime",
                   tolerated: [.followUp(["mom", "visit"])]),
        CorpusCase(id: "interview-yesterday",
                   note: "She had her interview yesterday and thinks it went okay.",
                   tolerated: [.followUp(["interview"])]),
    ]
}
