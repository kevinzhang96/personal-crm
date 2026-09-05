// The fallback summary, and the brief the model is handed.

import Foundation
import Testing
@testable import Tend

struct SummaryTests {
    let calendar = Calendar(identifier: .gregorian)
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 12))! }
    func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: now)! }

    var input: SummaryInput {
        SummaryInput(
            name: "Priya", circle: "Close",
            facts: [.init(label: "Partner", value: "Marco"), .init(label: "Gift idea", value: "pour-over kettle")],
            entries: [
                .init(date: day(-3), kind: "Call", text: "Long call. Her interview at Figma is next Thursday and she is nervous.", countsAsContact: true),
                .init(date: day(-20), kind: "Note", text: "Mentioned wanting a kettle", countsAsContact: false),
            ],
            reminders: [.init(title: "Ask how the interview went", due: day(5))])
    }

    @Test("standing, facts, latest notes, what's next — one line each")
    func compose() {
        let text = HeuristicSummary.compose(input, now: now, calendar: calendar)
        #expect(text == """
            Close friend · last talked 3d ago (call).
            Partner Marco · Gift idea pour-over kettle.
            Lately: Sep 5 — Long call. Aug 19 — Mentioned wanting a kettle
            Up next: Ask how the interview went (Sun, Sep 13).
            """)
    }

    @Test("notes without a conversation say so; nothing at all says nothing")
    func edges() {
        var notesOnly = input
        notesOnly.entries = [input.entries[1]]
        notesOnly.facts = []
        notesOnly.reminders = []
        #expect(HeuristicSummary.compose(notesOnly, now: now, calendar: calendar).hasPrefix("Close friend · notes only"))
        let empty = SummaryInput(name: "X", circle: "Friends", facts: [], entries: [], reminders: [])
        #expect(HeuristicSummary.compose(empty, now: now, calendar: calendar) == "")
    }

    @Test("the brief is dated, newest first, and bounded")
    func brief() {
        let text = HeuristicSummary.brief(input, now: now)
        #expect(text.hasPrefix("Friend: Priya (close circle).\nFacts: Partner: Marco; Gift idea: pour-over kettle.\nNotes, newest first:\n- 2026-09-05 (3d ago, call): Long call."))
        #expect(text.hasSuffix("Open follow-ups: Ask how the interview went due 2026-09-13."))
        var long = input
        long.entries = (0..<20).map { .init(date: day(-$0), kind: "Note", text: String(repeating: "x", count: 500), countsAsContact: false) }
        let bounded = HeuristicSummary.brief(long, now: now)
        #expect(bounded.components(separatedBy: "\n- ").count - 1 == HeuristicSummary.maxEntries)
        #expect(bounded.contains(String(repeating: "x", count: HeuristicSummary.maxEntryChars) + "…"))
    }

    @Test("first sentence, capped")
    func firstSentence() {
        #expect(HeuristicSummary.firstSentence("Long call. Then more.") == "Long call.")
        #expect(HeuristicSummary.firstSentence("no punctuation at all") == "no punctuation at all")
        #expect(HeuristicSummary.firstSentence(String(repeating: "a", count: 200)) == String(repeating: "a", count: 140) + "…")
    }
}
