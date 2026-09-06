// What a note implies: a follow-up on an event it mentions, or a fact
// worth keeping. The heuristic extractor here is deterministic and
// always available; Services/Extractor.swift puts the on-device language
// model in front of it when the device has one. Both only propose, and
// both are read by the same rules (Grounding) before the reader sees a
// word: an event needs a day or a clear "ahead", a fact needs the note's
// own words, and anything less is left out.

import Foundation

struct Suggestion: Identifiable, Equatable {
    enum Kind: Equatable {
        case followUp(due: Date)
        case fact
    }

    let id: UUID
    let kind: Kind
    /// Follow-up: what to do. Fact: the label.
    let title: String
    /// Follow-up: why (the sentence). Fact: the value.
    let detail: String

    var isFollowUp: Bool {
        if case .followUp = kind { return true }
        return false
    }

    var dueDate: Date? {
        if case .followUp(let due) = kind { return due }
        return nil
    }

    static func followUp(_ title: String, due: Date, because detail: String) -> Suggestion {
        Suggestion(id: UUID(), kind: .followUp(due: due), title: title, detail: detail)
    }

    static func fact(_ label: String, _ value: String) -> Suggestion {
        Suggestion(id: UUID(), kind: .fact, title: label, detail: value)
    }

    /// The same proposal, whichever sentence produced it: a follow-up is
    /// its question and its day; a fact is its label and value.
    func sameAs(_ other: Suggestion) -> Bool {
        guard kind == other.kind, title == other.title else { return false }
        return isFollowUp || detail == other.detail
    }
}

struct HeuristicExtractor: SuggestionProposer {
    var calendar = Calendar.current
    /// Follow-ups land the morning after the event.
    static let followUpHour = 9

    /// When to follow up on an event: the morning after it, or after
    /// today if it has already passed; an undated one is taken to be
    /// about a week out. The one place this rule lives, whoever found
    /// the event.
    static func followUpDue(after eventDay: Date?, now: Date, calendar: Calendar) -> Date {
        let day = eventDay.map { max($0, now) } ?? calendar.date(byAdding: .day, value: 6, to: now) ?? now
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? day
        return Dates.at(hour: followUpHour, on: nextDay, calendar: calendar)
    }

    func propose(note: String, now: Date) async throws -> [Suggestion] {
        suggestions(for: note, now: now)
    }

    /// The heuristic has no second draft in it; what stood, stands.
    func revise(note: String, kept: [Suggestion], rejected: [Rejection], now: Date) async throws -> [Suggestion] {
        kept
    }

    func suggestions(for text: String, now: Date) -> [Suggestion] {
        var out: [Suggestion] = []
        for sentence in Self.sentences(text) {
            if let followUp = followUp(in: sentence, now: now) { out.append(followUp) }
            out += Self.facts(in: sentence)
        }
        return out.reduce(into: []) { acc, s in
            if !acc.contains(where: { $0.sameAs(s) }) { acc.append(s) }
        }
    }

    // MARK: follow-ups

    private func followUp(in sentence: String, now: Date) -> Suggestion? {
        guard let title = Self.eventTitle(in: sentence) else { return nil }
        // The note-writer's own interview is not the friend's.
        guard Self.aboutSelf.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)) == nil else { return nil }
        let explicit = Self.date(in: sentence, now: now, calendar: calendar)
        if let explicit {
            // An event more than a few days gone is a story, not a follow-up.
            if Dates.daysBetween(explicit, now, calendar: calendar) > 3 { return nil }
        } else if Self.futureMarker.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)) == nil {
            return nil
        }
        return .followUp(title, due: Self.followUpDue(after: explicit, now: now, calendar: calendar), because: sentence)
    }

    /// The first event word the sentence mentions, with what to ask.
    static func eventTitle(in sentence: String) -> String? {
        let range = NSRange(sentence.startIndex..., in: sentence)
        return events.first { $0.pattern.firstMatch(in: sentence, range: range) != nil }?.title
    }

    /// The day a sentence points at, relative phrases first, then the
    /// detector for absolute dates. Also what the model's answer is checked
    /// against: a small model cannot do calendar arithmetic, this can.
    static func date(in sentence: String, now: Date, calendar: Calendar) -> Date? {
        if let relative = relativeDate(in: sentence, now: now, calendar: calendar) { return relative }
        // The detector resolves against the wall clock, which is fine for
        // absolute dates ("Sept 14", "on the 20th") — the only ones left
        // once the relative phrases above have had first refusal.
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(sentence.startIndex..., in: sentence)
        return detector.matches(in: sentence, range: range).compactMap(\.date).first
    }

    /// Phrases the calendar can resolve without a detector, against `now`.
    static func relativeDate(in sentence: String, now: Date, calendar: Calendar) -> Date? {
        let lower = sentence.lowercased()
        let today = calendar.startOfDay(for: now)
        func days(_ n: Int) -> Date? { calendar.date(byAdding: .day, value: n, to: today) }
        func weekday(_ index: Int, strictlyAfter: Bool) -> Date? {
            let current = calendar.component(.weekday, from: today)
            var delta = (index - current + 7) % 7
            if delta == 0 && strictlyAfter { delta = 7 }
            return days(delta)
        }

        if lower.contains("day after tomorrow") { return days(2) }
        if lower.range(of: "\\byesterday\\b", options: .regularExpression) != nil { return days(-1) }
        if lower.range(of: "\\btomorrow\\b", options: .regularExpression) != nil { return days(1) }
        if lower.contains("last week") { return days(-7) }
        if lower.contains("last month") { return calendar.date(byAdding: .month, value: -1, to: today) }
        if lower.range(of: "\\b(tonight|today|later today)\\b", options: .regularExpression) != nil { return today }
        if lower.contains("next weekend") { return weekday(7, strictlyAfter: true).flatMap { calendar.date(byAdding: .day, value: 7, to: $0) } }
        if lower.contains("this weekend") {
            let current = calendar.component(.weekday, from: today)
            return current == 1 ? today : weekday(7, strictlyAfter: false)
        }
        if lower.contains("next week") { return days(7) }
        if lower.contains("next month") { return calendar.date(byAdding: .month, value: 1, to: today) }
        if lower.contains("this week") { return weekday(6, strictlyAfter: false) }
        if let m = lower.range(of: "\\bin (a|an|one|two|three|four|five|six|seven|eight|nine|ten|a couple of|a few|\\d+) (day|week|month)s?\\b", options: .regularExpression) {
            let words = lower[m].split(separator: " ").map(String.init)
            let unit = words.last!.hasPrefix("day") ? Calendar.Component.day : words.last!.hasPrefix("week") ? .weekOfYear : .month
            let count = Self.number(words.dropFirst().dropLast().joined(separator: " "))
            return calendar.date(byAdding: unit, value: count, to: today)
        }
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        for (i, name) in names.enumerated() {
            // "last Thursday" is behind us, however near the next one is.
            if lower.range(of: "\\blast \(name)\\b", options: .regularExpression) != nil {
                return weekday(i + 1, strictlyAfter: false).flatMap { calendar.date(byAdding: .day, value: -7, to: $0) }
            }
            if lower.range(of: "\\bnext \(name)\\b", options: .regularExpression) != nil { return weekday(i + 1, strictlyAfter: true) }
            if lower.range(of: "\\b(this |on )?\(name)\\b", options: .regularExpression) != nil { return weekday(i + 1, strictlyAfter: false) }
        }
        return nil
    }

    private static func number(_ word: String) -> Int {
        switch word {
        case "a", "an", "one": 1
        case "two", "a couple of": 2
        case "three", "a few": 3
        case "four": 4
        case "five": 5
        case "six": 6
        case "seven": 7
        case "eight": 8
        case "nine": 9
        case "ten": 10
        default: Int(word) ?? 1
        }
    }

    // MARK: facts

    static func facts(in sentence: String) -> [Suggestion] {
        let range = NSRange(sentence.startIndex..., in: sentence)
        return factPatterns.compactMap { rule in
            guard let match = rule.pattern.firstMatch(in: sentence, range: range) else { return nil }
            let groups = (1..<match.numberOfRanges).compactMap { i -> String? in
                guard let r = Range(match.range(at: i), in: sentence) else { return nil }
                return String(sentence[r])
            }
            guard let value = rule.value(groups)?.trimmingCharacters(in: Self.trailingPunctuation), !value.isEmpty else { return nil }
            return .fact(rule.label, value)
        }
    }

    // MARK: tables

    private struct Event {
        let pattern: NSRegularExpression
        let title: String
        init(_ pattern: String, _ title: String) {
            self.pattern = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            self.title = title
        }
    }

    /// Words that name an occasion in someone's life. Each is specific
    /// enough to be one: "match", "scan", "results" and "hearing" were
    /// here once and matched tennis, documents and listening.
    private static let events: [Event] = [
        Event("\\binterview", "Ask how the interview went"),
        Event("\\bsurgery|\\boperation\\b|\\bprocedure\\b", "Check in after the surgery"),
        Event("\\bwedding", "Ask about the wedding"),
        Event("\\bfuneral|\\bpassed away|\\bmemorial", "Check in on how they're doing"),
        Event("\\bdue date\\b|\\bbaby('s| is) due\\b|\\bexpecting\\b|\\bhaving a baby\\b|\\bbaby (comes|arrives)\\b", "Check in about the baby"),
        Event("\\bexams?\\b|\\bfinals\\b|\\bbar exam|\\bthesis defen[cs]e|\\bdissertation\\b", "Ask how the exam went"),
        Event("\\bpresentation|\\bpitch\\b|\\bdemo day\\b|\\bkeynote|\\bgiving a talk|\\btalk at\\b", "Ask how the presentation went"),
        Event("\\bnew job\\b|\\bfirst day\\b", "Ask how the new job is going"),
        Event("\\bmoving (to|into|out|house|home|in)\\b|\\bthe move\\b|\\bnew (house|place|apartment|flat)\\b|\\bclosing on\\b", "Ask how the move went"),
        Event("\\btrip\\b|\\bvacation|\\bholiday\\b|\\bflight\\b|\\bflying (to|out|home|back)\\b|\\btravel+ing to\\b", "Ask how the trip was"),
        Event("\\bmarathon|\\btriathlon|\\brace day\\b|\\btournament|\\bcompetition|\\bbig game\\b", "Ask how the race went"),
        Event("\\bappointment\\b|\\bcheck-?up\\b|\\bbiopsy|\\bMRI\\b|\\bspecialist\\b", "Ask how the appointment went"),
        Event("\\blaunch(es|ing)?\\b|\\bdeadline\\b|\\bship date\\b", "Ask how the launch went"),
        Event("\\bconference|\\bsummit\\b|\\bhackathon|\\boffsite", "Ask how the conference was"),
        Event("\\brecital|\\bconcert|\\bgig\\b|\\bopening night|\\bperformance\\b(?! review)", "Ask how the show went"),
        Event("\\bcourt (date|hearing)|\\bcustody hearing|\\bthe trial\\b", "Ask how the hearing went"),
        Event("\\bbirthday party|\\bhousewarming|\\banniversary\\b|\\bparty\\b", "Ask how the party was"),
        Event("\\bdate night|\\bfirst date\\b", "Ask how the date went"),
    ]

    /// Words that put an undated event ahead rather than behind. "has a"
    /// and "getting" were here once and put every possession in the future.
    private static let futureMarker = try! NSRegularExpression(
        pattern: "\\b(will|going to|gonna|next|soon|upcoming|coming up|about to|planning to|plans to|is (having|giving|starting|leaving|flying))\\b",
        options: .caseInsensitive)

    /// A sentence the note-writer opens about themselves.
    private static let aboutSelf = try! NSRegularExpression(
        pattern: "^\\W*(I|I'm|I’m|I've|I’ve|I'll|I’ll|My)\\b", options: [])

    private struct FactRule {
        let pattern: NSRegularExpression
        let label: String
        let value: ([String]) -> String?
        init(_ pattern: String, _ label: String, _ value: @escaping ([String]) -> String? = { $0.first }) {
            self.pattern = try! NSRegularExpression(pattern: pattern, options: [])
            self.label = label
            self.value = value
        }
    }

    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?").union(.whitespaces)
    private static let name = "[A-Z][a-zA-Z'\\-]+"
    private static let place = "[A-Z][a-zA-Z.\\-]*(?: [A-Z][a-zA-Z.\\-]*){0,2}"

    /// Each takes only the phrasing that states the fact: "working with
    /// Sarah" is not an employer, "would love to see you" is not a gift,
    /// "her son is Tall" is not a name.
    private static let factPatterns: [FactRule] = [
        FactRule("(?i:her|his|their) (?i:wife|husband|partner|girlfriend|boyfriend|fianc[ée]e?|spouse)(?i:,| is| is named| is called| named| called)? (\(name))", "Partner"),
        FactRule("(?i:works|working|job|started|starting|interning|new role) (?i:at|for) (\(place))", "Works at"),
        FactRule("(?i:moved|moving|lives|living|relocated|relocating) (?i:to|in|into|back to) (\(place))", "Lives in"),
        FactRule("(?i:daughter|son|kids?|children?|twins)\\b[^.!?]*?\\b(?i:named|called) (\(name)(?: (?:and|&) \(name))*)", "Kids"),
        FactRule("(?i:allergic to) ([a-zA-Z]+(?: (?:and|&) [a-zA-Z]+)*)", "Allergy"),
        FactRule("(?i:got|adopted|rescued) (?i:a |an )?(?i:new )?((?i:puppy|dog|cat|kitten|rabbit|parrot))(?: (?i:named|called) (\(name)))?", "Pets") { groups in
            groups.count > 1 ? "\(groups[1]) (\(groups[0].lowercased()))" : groups.first?.lowercased()
        },
        FactRule("(?i:been wanting|has been eyeing|really wants|would love) (?i:a|an|the) ([a-z][^.!?,;]{2,40})", "Gift idea"),
    ]

    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .localized]) { s, _, _, _ in
            if let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { out.append(s) }
        }
        return out
    }
}
