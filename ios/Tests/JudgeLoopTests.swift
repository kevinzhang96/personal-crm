// The loop, driven by stand-ins: what reaches the judge, what a rejection
// does, when it stops, and how it degrades.

import Foundation
import Testing
@testable import Tend

struct JudgeLoopTests {
    let calendar = Calendar(identifier: .gregorian)
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 15))! }
    var loop: JudgeLoop { JudgeLoop(maxRounds: 2, calendar: calendar) }

    let note = "Priya said her interview at Figma is next Thursday and she's nervous. Her husband Marco just started at Anthropic."
    var interview: Suggestion {
        .followUp("Ask how the interview went", due: calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 9))!,
                  because: "Priya said her interview at Figma is next Thursday and she's nervous.")
    }
    var partner: Suggestion { .fact("Partner", "Marco") }
    /// Not in the note: the rules drop it before any judge sees it.
    var invented: Suggestion { .fact("Lives in", "Lisbon") }

    struct Failure: Error {}

    /// Answers with a first draft, then a second, and remembers what it was told.
    final class Proposer: SuggestionProposer {
        var drafts: [[Suggestion]]
        var critiques: [[Rejection]] = []
        var fails = false
        init(_ drafts: [[Suggestion]]) { self.drafts = drafts }

        func propose(note: String, now: Date) async throws -> [Suggestion] {
            if fails { throw Failure() }
            return drafts.first ?? []
        }

        func revise(note: String, kept: [Suggestion], rejected: [Rejection], now: Date) async throws -> [Suggestion] {
            critiques.append(rejected)
            return drafts.count > critiques.count ? drafts[critiques.count] : kept
        }
    }

    /// Rejects by title, a different list each round, and remembers what it saw.
    final class Judge: SuggestionJudge {
        var rejects: [[String]]
        var seen: [[Suggestion]] = []
        var fails = false
        init(_ rejects: [[String]]) { self.rejects = rejects }

        func review(note: String, proposals: [Suggestion], now: Date) async throws -> [Rejection] {
            if fails { throw Failure() }
            seen.append(proposals)
            let round = seen.count - 1
            guard round < rejects.count else { return [] }
            return proposals.filter { rejects[round].contains($0.title) }.map { Rejection(suggestion: $0, reason: "not in the note") }
        }
    }

    @Test("a first draft the judge accepts is done in one round")
    func approvedAtOnce() async throws {
        let proposer = Proposer([[interview, partner]])
        let judge = Judge([[]])
        let out = try await loop.run(note: note, now: now, proposer: proposer, judge: judge)
        #expect(out.suggestions.map(\.title) == ["Ask how the interview went", "Partner"])
        #expect(out.rounds == 1)
        #expect(out.approved)
        #expect(out.rejected.isEmpty)
        #expect(proposer.critiques.isEmpty)
    }

    @Test("a rejection goes back to the proposer, and the second draft is judged again")
    func revised() async throws {
        let proposer = Proposer([[interview, partner], [interview]])
        let judge = Judge([["Partner"], []])
        var stages: [JudgeLoop.Stage] = []
        let out = try await loop.run(note: note, now: now, proposer: proposer, judge: judge) { stages.append($0) }
        #expect(out.suggestions.map(\.title) == ["Ask how the interview went"])
        #expect(out.rounds == 2)
        #expect(out.approved)
        #expect(out.rejected.map(\.reason) == ["not in the note"])
        #expect(proposer.critiques.count == 1)
        #expect(proposer.critiques.first?.first?.suggestion.title == "Partner")
        #expect(stages == [.proposing, .judging(round: 1), .revising(round: 1), .judging(round: 2)])
    }

    @Test("what the judge set aside stays aside, whatever the second draft says")
    func banned() async throws {
        let proposer = Proposer([[interview, partner], [interview, partner]])
        let judge = Judge([["Partner"], []])
        let out = try await loop.run(note: note, now: now, proposer: proposer, judge: judge)
        #expect(out.suggestions.map(\.title) == ["Ask how the interview went"])
        #expect(judge.seen.last?.map(\.title) == ["Ask how the interview went"])
    }

    @Test("at the cap the last verdict trims and nothing is revised")
    func capped() async throws {
        let proposer = Proposer([[interview, partner]])
        let judge = Judge([["Partner"], ["Ask how the interview went"]])
        let out = try await JudgeLoop(maxRounds: 1, calendar: calendar).run(note: note, now: now, proposer: proposer, judge: judge)
        #expect(out.suggestions.map(\.title) == ["Ask how the interview went"])
        #expect(out.rounds == 1)
        #expect(!out.approved)
        #expect(proposer.critiques.isEmpty)
    }

    @Test("the rules run before the judge, so it only sees what the note supports")
    func groundedFirst() async throws {
        let proposer = Proposer([[interview, invented, partner]])
        let judge = Judge([[]])
        let out = try await loop.run(note: note, now: now, proposer: proposer, judge: judge)
        #expect(judge.seen.first?.map(\.title) == ["Ask how the interview went", "Partner"])
        #expect(out.rejected.map(\.reason) == ["uses words the note doesn't: lisbon"])
    }

    @Test("without a judge the grounded first draft is the answer")
    func noJudge() async throws {
        let out = try await loop.run(note: note, now: now, proposer: Proposer([[interview, invented]]), judge: nil)
        #expect(out.suggestions.map(\.title) == ["Ask how the interview went"])
        #expect(out.rounds == 0)
        #expect(!out.approved)
    }

    @Test("a judge that cannot answer leaves the grounded draft as it is")
    func judgeDown() async throws {
        let judge = Judge([])
        judge.fails = true
        let out = try await loop.run(note: note, now: now, proposer: Proposer([[interview, partner]]), judge: judge)
        #expect(out.suggestions.count == 2)
        #expect(out.rounds == 1)
        #expect(!out.approved)
    }

    @Test("a proposer that cannot answer is the caller's problem")
    func proposerDown() async {
        let proposer = Proposer([])
        proposer.fails = true
        await #expect(throws: Failure.self) {
            try await loop.run(note: note, now: now, proposer: proposer, judge: nil)
        }
    }

    @Test("the heuristic is a proposer with no second draft in it")
    func heuristicAsProposer() async throws {
        let out = try await loop.run(note: note, now: now, proposer: HeuristicExtractor(calendar: calendar), judge: Judge([[]]))
        #expect(out.suggestions.map(\.title) == ["Ask how the interview went", "Partner", "Works at"])
        #expect(out.approved)
    }
}
