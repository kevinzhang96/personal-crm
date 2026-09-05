// The morning notification: who is in it, in what order, and what it says.

import Foundation
import Testing
@testable import Tend

struct DigestTests {
    let calendar = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 1_788_000_000)
    func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: now)! }

    func person(_ name: String, last: Int?, every: Int?, snoozed: Date? = nil) -> DigestCandidate {
        DigestCandidate(name: name, lastContact: last.map(day), cadenceDays: every, snoozedUntil: snoozed, createdAt: day(-400))
    }

    @Test("only the overdue appear, longest overdue first")
    func selection() {
        let lines = Digest.overdue([
            person("Ana", last: -10, every: 7),      // 3 over
            person("Ben", last: -1, every: 7),       // fine
            person("Cy", last: -100, every: 30),     // 70 over
            person("Di", last: -100, every: nil),    // never nudged
            person("Ed", last: -100, every: 30, snoozed: day(2)),
        ], on: now, calendar: calendar)
        #expect(lines == [DigestLine(name: "Cy", overdueDays: 70), DigestLine(name: "Ana", overdueDays: 3)])
    }

    @Test("asked about a later morning, the digest includes who will be overdue by then")
    func future() {
        let people = [person("Ana", last: -5, every: 7)]
        #expect(Digest.overdue(people, on: now, calendar: calendar).isEmpty)
        #expect(Digest.overdue(people, on: day(3), calendar: calendar) == [DigestLine(name: "Ana", overdueDays: 1)])
    }

    @Test("nothing overdue is no notification")
    func empty() {
        #expect(Digest.content(for: []) == nil)
    }

    @Test("one name reads as a sentence; many read as a list with a remainder")
    func wording() {
        #expect(Digest.content(for: [DigestLine(name: "Ana", overdueDays: 3)])
                == DigestContent(title: "Catch up with Ana", body: "3d past your usual — say hi?"))
        let many = (1...5).map { DigestLine(name: "P\($0)", overdueDays: 10 - $0) }
        #expect(Digest.content(for: many)
                == DigestContent(title: "Catch up with 5 friends", body: "P1 · 9d, P2 · 8d, P3 · 7d +2 more"))
    }
}
