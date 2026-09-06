// The corpus through the pipeline. The pattern-matching path runs every
// time and must propose nothing the corpus doesn't ask for. The real
// on-device model runs only when asked (TEND_MODEL_EVAL=1), because it
// takes minutes and answers differently each time; that run writes a
// trace of every draft, every rule that fired and every verdict, which
// is what the prompts are tuned against.
//
//   TEND_EVAL_READING / TEND_EVAL_JUDGE  files overriding the two prompts
//   TEND_EVAL_ROUNDS                     judge rounds (default: the app's)
//   TEND_EVAL_ONLY                       comma-separated case ids
//   TEND_EVAL_OUT / TEND_EVAL_LABEL      where the report goes, and its name

import Foundation
import Testing
@testable import Tend

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Remembers each draft the proposer made.
final class TracingProposer: SuggestionProposer {
    let inner: SuggestionProposer
    var drafts: [(stage: String, items: [Suggestion])] = []
    init(_ inner: SuggestionProposer) { self.inner = inner }

    func propose(note: String, now: Date) async throws -> [Suggestion] {
        let d = try await inner.propose(note: note, now: now)
        drafts.append(("draft", d))
        return d
    }

    func revise(note: String, kept: [Suggestion], rejected: [Rejection], now: Date) async throws -> [Suggestion] {
        let d = try await inner.revise(note: note, kept: kept, rejected: rejected, now: now)
        drafts.append(("revision", d))
        return d
    }
}

/// Remembers what the judge saw and what it sent back.
final class TracingJudge: SuggestionJudge {
    let inner: SuggestionJudge
    var reviews: [(seen: [Suggestion], rejected: [Rejection])] = []
    init(_ inner: SuggestionJudge) { self.inner = inner }

    func review(note: String, proposals: [Suggestion], now: Date) async throws -> [Rejection] {
        let r = try await inner.review(note: note, proposals: proposals, now: now)
        reviews.append((proposals, r))
        return r
    }
}

struct CaseTrace {
    let c: CorpusCase
    let drafts: [(stage: String, items: [Suggestion])]
    let reviews: [(seen: [Suggestion], rejected: [Rejection])]
    let outcome: JudgeOutcome
    let score: CaseScore
    let seconds: Double
    let error: String?

    /// Rejections the rules made, as opposed to the judge.
    var byRules: [Rejection] {
        let byJudge = reviews.flatMap(\.rejected)
        return outcome.rejected.filter { r in !byJudge.contains(r) }
    }

    static func line(_ s: Suggestion) -> String {
        s.isFollowUp
            ? "follow-up “\(s.title)” (\(s.dueDate!.formatted(.iso8601.year().month().day()))) ← “\(s.detail)”"
            : "fact \(s.title): \(s.detail)"
    }

    var markdown: String {
        var out = ["### \(c.id) — tp \(score.truePositives.count) · fp \(score.falsePositives.count) · fn \(score.falseNegatives.count) · \(Int(seconds))s · rounds \(outcome.rounds)\(outcome.approved ? " · approved" : "")",
                   "", "> \(c.note)", ""]
        if let error { out.append("- **error**: \(error)") }
        for (i, d) in drafts.enumerated() {
            out.append("- \(d.stage) \(i + 1): " + (d.items.isEmpty ? "(nothing)" : d.items.map(Self.line).joined(separator: " · ")))
        }
        for r in byRules { out.append("- rules dropped: \(Self.line(r.suggestion)) — _\(r.reason)_") }
        for (i, r) in reviews.enumerated() {
            out.append("- judge \(i + 1) saw \(r.seen.count): " + (r.rejected.isEmpty ? "kept all" : r.rejected.map { "rejected \(Self.line($0.suggestion)) — _\($0.reason)_" }.joined(separator: " · ")))
        }
        out.append("- **final**: " + (outcome.suggestions.isEmpty ? "(nothing)" : outcome.suggestions.map(Self.line).joined(separator: " · ")))
        for s in score.falsePositives { out.append("- ❌ false positive: \(Self.line(s))") }
        for e in score.falseNegatives { out.append("- ❌ missed: \(e.short)") }
        for s in score.toleratedHits { out.append("- ~ tolerated: \(Self.line(s))") }
        return out.joined(separator: "\n") + "\n"
    }
}

struct PromptEvalTests {
    static let env = ProcessInfo.processInfo.environment
    static var modelEval: Bool { env["TEND_MODEL_EVAL"] == "1" }

    static var cases: [CorpusCase] {
        guard let only = env["TEND_EVAL_ONLY"], !only.isEmpty else { return PromptCorpus.cases }
        let ids = Set(only.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        return PromptCorpus.cases.filter { ids.contains($0.id) }
    }

    static func text(at path: String?) -> String? {
        guard let path, !path.isEmpty, let s = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @Test("pattern matching proposes nothing the corpus doesn't ask for, and finds what it can")
    func heuristic() async throws {
        let loop = JudgeLoop(maxRounds: 0, calendar: PromptCorpus.calendar)
        var scores: [CaseScore] = []
        for c in PromptCorpus.cases {
            let out = try await loop.run(note: c.note, now: PromptCorpus.now,
                                         proposer: HeuristicExtractor(calendar: PromptCorpus.calendar), judge: nil)
            let s = CaseScore.score(out.suggestions, against: c)
            #expect(s.falsePositives.isEmpty, "\(c.id) proposed \(s.falsePositives.map(CaseTrace.line))")
            let missed = s.falseNegatives.filter { !c.modelOnly.contains($0) }
            #expect(missed.isEmpty, "\(c.id) missed \(missed.map(\.short))")
            scores.append(s)
        }
        print("HEURISTIC " + CorpusMetrics(scores, corpus: PromptCorpus.cases).description)
    }

    /// The old extractor's habits against the rules alone, then against
    /// the rules and a judge applying the judge prompt's criteria. What
    /// survives the rules is what the judge prompt has to name.
    @Test("an eager proposer: what the rules catch alone, and what the judge must")
    func eager() async throws {
        let calendar = PromptCorpus.calendar
        var rulesOnly: [CaseScore] = [], judged: [CaseScore] = []
        var proposed: [String: Int] = [:], pastRules: [String: Int] = [:], pastJudge: [String: Int] = [:]
        for c in PromptCorpus.cases {
            let eager = EagerStandIn(calendar: calendar)
            let draft = try await eager.propose(note: c.note, now: PromptCorpus.now)
            for s in draft { proposed[eager.modes[s.id] ?? "?", default: 0] += 1 }
            let rules = Grounding.review(draft, note: c.note, now: PromptCorpus.now, calendar: calendar)
            let alone = CaseScore.score(rules.kept, against: c)
            for s in alone.falsePositives { pastRules["\(eager.modes[s.id] ?? "?") (\(c.id))", default: 0] += 1 }
            rulesOnly.append(alone)

            let again = EagerStandIn(calendar: calendar)
            let out = try await JudgeLoop(maxRounds: 2, calendar: calendar)
                .run(note: c.note, now: PromptCorpus.now, proposer: again, judge: StandInJudge())
            let both = CaseScore.score(out.suggestions, against: c)
            for s in both.falsePositives { pastJudge["\(again.modes[s.id] ?? "?") (\(c.id))", default: 0] += 1 }
            #expect(both.falsePositives.isEmpty, "\(c.id) kept \(both.falsePositives.map(CaseTrace.line))")
            let missed = both.falseNegatives.filter { !c.modelOnly.contains($0) }
            #expect(missed.isEmpty, "\(c.id) missed \(missed.map(\.short))")
            judged.append(both)
        }
        func list(_ d: [String: Int]) -> String { d.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ") }
        print("EAGER proposed: \(list(proposed))")
        print("EAGER rules alone: \(CorpusMetrics(rulesOnly, corpus: PromptCorpus.cases)) · past the rules: \(list(pastRules))")
        print("EAGER rules + judge: \(CorpusMetrics(judged, corpus: PromptCorpus.cases)) · past the judge: \(list(pastJudge))")
    }

    @Test("the on-device model: proposer, rules and judge over the corpus", .enabled(if: PromptEvalTests.modelEval))
    func model() async throws {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return }
        guard FoundationProposer.isAvailable else {
            Issue.record("the on-device model is not available in this process")
            return
        }
        let reading = Self.text(at: Self.env["TEND_EVAL_READING"]) ?? Prompts.extractor
        let judging = Self.text(at: Self.env["TEND_EVAL_JUDGE"]) ?? Prompts.judge
        let rounds = Int(Self.env["TEND_EVAL_ROUNDS"] ?? "") ?? Prompts.defaultRounds
        let outDir = Self.env["TEND_EVAL_OUT"] ?? NSTemporaryDirectory()
        let label = Self.env["TEND_EVAL_LABEL"] ?? "run"
        let progress = URL(fileURLWithPath: outDir).appendingPathComponent("progress-\(label).log")
        try? "".write(to: progress, atomically: true, encoding: .utf8)
        func note(_ line: String) {
            if let h = try? FileHandle(forWritingTo: progress) {
                h.seekToEndOfFile()
                h.write(Data((line + "\n").utf8))
                try? h.close()
            }
        }

        let loop = JudgeLoop(maxRounds: rounds, calendar: PromptCorpus.calendar)
        var traces: [CaseTrace] = []
        for c in Self.cases {
            let proposer = TracingProposer(FoundationProposer(instructions: reading))
            let judge = TracingJudge(FoundationJudge(instructions: judging))
            let started = Date()
            var outcome = JudgeOutcome.empty
            var error: String?
            do {
                outcome = try await loop.run(note: c.note, now: PromptCorpus.now, proposer: proposer, judge: judge)
            } catch let e {
                error = "\(e)"
            }
            let score = CaseScore.score(outcome.suggestions, against: c)
            let trace = CaseTrace(c: c, drafts: proposer.drafts, reviews: judge.reviews, outcome: outcome, score: score,
                                  seconds: Date().timeIntervalSince(started), error: error)
            traces.append(trace)
            note("\(c.id): tp \(score.truePositives.count) fp \(score.falsePositives.count) fn \(score.falseNegatives.count) (\(Int(trace.seconds))s, rounds \(outcome.rounds))"
                 + (error.map { " error: \($0)" } ?? ""))
        }

        let metrics = CorpusMetrics(traces.map(\.score), corpus: Self.cases)
        var report = ["# Prompt eval — \(label)", "", "**\(metrics)**", "",
                      "False positives in: \(metrics.casesWithFalsePositives.joined(separator: ", "))",
                      "Missed in: \(metrics.casesWithFalseNegatives.joined(separator: ", "))", "",
                      "Reading prompt (\(reading.count) chars), judge prompt (\(judging.count) chars), rounds \(rounds).", ""]
        report += traces.map(\.markdown)
        let file = URL(fileURLWithPath: outDir).appendingPathComponent("eval-\(label).md")
        try report.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        note("DONE \(metrics)")
        print("MODEL EVAL \(label): \(metrics) → \(file.path)")
        #endif
    }
}
