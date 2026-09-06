// The heuristic extractor, on the notes it is meant for.

import Foundation
import Testing
@testable import Tend

struct SuggestionTests {
    let calendar = Calendar(identifier: .gregorian)
    // Saturday 2026-09-05, 15:00.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 15))! }
    var extractor: HeuristicExtractor { HeuristicExtractor(calendar: calendar) }

    func ymd(_ date: Date) -> DateComponents { calendar.dateComponents([.year, .month, .day, .hour], from: date) }

    @Test("an event next week becomes a follow-up the morning after it")
    func nextWeek() {
        let out = extractor.suggestions(for: "Priya said her interview at Figma is next week and she's nervous.", now: now)
        let follow = out.first(where: \.isFollowUp)
        #expect(follow?.title == "Ask how the interview went")
        // next week = +7d = Sept 12; follow up Sept 13 at 09:00
        #expect(follow.flatMap(\.dueDate).map(ymd) == DateComponents(year: 2026, month: 9, day: 13, hour: 9))
        #expect(follow?.detail.contains("interview") == true)
    }

    @Test("weekday names resolve to the coming one; 'next' skips a week")
    func weekdays() {
        // Sat Sep 5: "Thursday" is Sep 10, "next Thursday" is also the first Thursday strictly after today = Sep 10.
        let a = extractor.suggestions(for: "Sam has surgery on Thursday.", now: now).first!
        #expect(ymd(a.dueDate!) == DateComponents(year: 2026, month: 9, day: 11, hour: 9))
        let b = extractor.suggestions(for: "They are flying to Lisbon next Saturday.", now: now).first!
        #expect(ymd(b.dueDate!) == DateComponents(year: 2026, month: 9, day: 13, hour: 9))
        let c = extractor.suggestions(for: "Big presentation tomorrow!", now: now).first!
        #expect(ymd(c.dueDate!) == DateComponents(year: 2026, month: 9, day: 7, hour: 9))
    }

    @Test("'in N units' counts from today")
    func inUnits() {
        let out = extractor.suggestions(for: "The wedding is in three weeks.", now: now)
        #expect(ymd(out.first!.dueDate!) == DateComponents(year: 2026, month: 9, day: 27, hour: 9))
        let couple = extractor.suggestions(for: "Moving into the new place in a couple of days.", now: now)
        #expect(ymd(couple.first!.dueDate!) == DateComponents(year: 2026, month: 9, day: 8, hour: 9))
    }

    @Test("an undated event still gets a follow-up when it is clearly ahead, and none when it is past")
    func undated() {
        let ahead = extractor.suggestions(for: "She's going to run a marathon soon.", now: now)
        #expect(ahead.first?.isFollowUp == true)
        #expect(ymd(ahead.first!.dueDate!) == DateComponents(year: 2026, month: 9, day: 12, hour: 9))
        let past = extractor.suggestions(for: "We talked about the marathon she ran in 2019.", now: now)
        #expect(past.filter(\.isFollowUp).isEmpty)
        let plain = extractor.suggestions(for: "We had coffee and caught up about work.", now: now)
        #expect(plain.isEmpty)
    }

    @Test("facts come out labelled")
    func facts() {
        let out = extractor.suggestions(for: "Her husband Marco just started at Anthropic. They moved to Oakland last month. Their daughter is called Lu.", now: now)
        let facts = out.filter { !$0.isFollowUp }.map { ($0.title, $0.detail) }
        #expect(facts.contains { $0 == ("Partner", "Marco") })
        // The husband's employer is his, not hers.
        #expect(!facts.contains { $0.0 == "Works at" })
        #expect(facts.contains { $0 == ("Lives in", "Oakland") })
        #expect(facts.contains { $0 == ("Kids", "Lu") })
    }

    @Test("gift ideas and pets and allergies")
    func moreFacts() {
        let out = extractor.suggestions(for: "He's been wanting a pour-over kettle for ages. Got a puppy named Biscuit. Allergic to shellfish and peanuts.", now: now)
        let facts = out.filter { !$0.isFollowUp }.map { ($0.title, $0.detail) }
        #expect(facts.contains { $0 == ("Gift idea", "pour-over kettle") })
        #expect(facts.contains { $0 == ("Pets", "Biscuit (puppy)") })
        #expect(facts.contains { $0 == ("Allergy", "shellfish and peanuts") })
    }

    @Test("the same event twice is one suggestion")
    func dedupe() {
        let out = extractor.suggestions(for: "Interview next week. Did I mention the interview is next week?", now: now)
        #expect(out.filter(\.isFollowUp).count == 1)
    }
}

// The bias toward leaving things out: what the heuristic no longer says.
struct ConservativeSuggestionTests {
    let calendar = Calendar(identifier: .gregorian)
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 15))! }
    var extractor: HeuristicExtractor { HeuristicExtractor(calendar: calendar) }

    @Test("a possession, a pastime and a phrase are not events")
    func notEvents() {
        for note in [
            "She has a baby and a dog.",
            "We watched the match on Saturday.",
            "Her performance review is next week.",
            "She's been hearing about the new place.",
            "They got the results back and everything is fine.",
            "She's flying a lot for work these days.",
        ] {
            #expect(extractor.suggestions(for: note, now: now).filter(\.isFollowUp).isEmpty, "\(note)")
        }
    }

    @Test("the note-writer's own event is not the friend's")
    func aboutSelf() {
        #expect(extractor.suggestions(for: "I have an interview on Monday.", now: now).isEmpty)
        #expect(extractor.suggestions(for: "My surgery is tomorrow.", now: now).isEmpty)
        #expect(!extractor.suggestions(for: "Her interview is on Monday.", now: now).isEmpty)
    }

    @Test("last week is behind us, however near the next one is")
    func lastWeek() {
        #expect(extractor.suggestions(for: "Her surgery was last Monday.", now: now).isEmpty)
        #expect(extractor.suggestions(for: "The wedding was last week.", now: now).isEmpty)
        let recent = extractor.suggestions(for: "Her surgery was yesterday.", now: now)
        #expect(recent.first?.title == "Check in after the surgery")
    }

    @Test("phrasings that sound like facts but aren't stay out")
    func notFacts() {
        for note in [
            "She's working with Sarah on the redesign.",
            "She would love to see you.",
            "He really wants to move somewhere warmer.",
            "Her son is Tall for his age.",
        ] {
            #expect(extractor.suggestions(for: note, now: now).filter { !$0.isFollowUp }.isEmpty, "\(note)")
        }
    }
}
