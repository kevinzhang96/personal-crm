// The rules every proposal passes through, whoever made it.

import Foundation
import Testing
@testable import Tend

struct GroundingTests {
    let calendar = Calendar(identifier: .gregorian)
    // Saturday 2026-09-05, 15:00.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 15))! }

    func day(_ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    func ymd(_ date: Date) -> DateComponents { calendar.dateComponents([.year, .month, .day, .hour], from: date) }

    func review(_ proposals: [Suggestion], note: String) -> Grounding.Review {
        Grounding.review(proposals, note: note, now: now, calendar: calendar)
    }

    // MARK: evidence

    @Test("evidence is the note's own sentence, not a paraphrase of it")
    func evidence() {
        let note = "Priya said her interview at Figma is next Thursday and she's nervous."
        #expect(Grounding.grounded("her interview at Figma is next Thursday", in: note))
        #expect(Grounding.grounded("Priya said her interview at Figma is next Thursday, and shes nervous", in: note))
        #expect(!Grounding.grounded("Priya has a job interview coming up at Figma", in: note))
        #expect(!Grounding.grounded("Figma interview", in: note))
        #expect(!Grounding.grounded("", in: note))
    }

    @Test("a follow-up whose sentence isn't in the note, or names no event and no day, is dropped")
    func followUpNeedsGroundedEvent() {
        let note = "Sam has surgery on Thursday. We had coffee and caught up about work."
        let invented = Suggestion.followUp("Ask about the wedding", due: day(9, 20), because: "Sam is getting married in the spring.")
        #expect(Grounding.vet(invented, note: note, now: now, calendar: calendar) == .drop("the evidence sentence isn't in the note"))
        let idle = Suggestion.followUp("Ask about work", due: day(9, 12), because: "We had coffee and caught up about work.")
        #expect(Grounding.vet(idle, note: note, now: now, calendar: calendar) == .drop("the sentence names no event and no day"))
    }

    @Test("the sentence's own day beats the proposer's, and the follow-up lands the morning after")
    func dayFromSentence() {
        let note = "Sam has surgery on Thursday."
        let wrongDay = Suggestion.followUp("Check in after the surgery", due: day(9, 20), because: note)
        let kept = review([wrongDay], note: note).kept
        #expect(kept.count == 1)
        #expect(kept.first.flatMap(\.dueDate).map(ymd) == DateComponents(year: 2026, month: 9, day: 11, hour: 9))
        #expect(kept.first?.id == wrongDay.id)
    }

    @Test("an event more than a few days gone, or a due day already passed, is dropped")
    func past() {
        let recent = "Her surgery was last Thursday."
        let justGone = Suggestion.followUp("Check in after the surgery", due: day(9, 6), because: recent)
        #expect(review([justGone], note: recent).kept.first.flatMap(\.dueDate).map(ymd) == DateComponents(year: 2026, month: 9, day: 6, hour: 9))
        let old = "Her surgery was last Monday."
        let story = Suggestion.followUp("Check in after the surgery", due: day(9, 6), because: old)
        #expect(Grounding.vet(story, note: old, now: now, calendar: calendar) == .drop("the event is already past"))
        let undated = "Her interview went well."
        let stale = Suggestion.followUp("Ask how the interview went", due: day(9, 1), because: undated)
        #expect(Grounding.vet(stale, note: undated, now: now, calendar: calendar) == .drop("the day to follow up has passed"))
    }

    @Test("the model path gets the rules the heuristic already had: the note-writer's own sentence, a year gone by, a hedge")
    func modelPathRules() {
        let mine = "I have an interview on Monday and asked him for tips."
        let own = Suggestion.followUp("Ask how the interview went", due: day(9, 8), because: mine)
        #expect(Grounding.vet(own, note: mine, now: now, calendar: calendar) == .drop("the sentence is about the note-writer"))
        let story = "We talked about the marathon she ran in 2019 and how she's been lazy since."
        let old = Suggestion.followUp("Ask how the marathon went", due: day(9, 12), because: story)
        #expect(Grounding.vet(old, note: story, now: now, calendar: calendar) == .drop("the event is already past"))
        let floated = "He mentioned he might look for a new job at some point, nothing concrete."
        let maybe = Suggestion.followUp("Ask how the new job is going", due: day(9, 12), because: floated)
        #expect(Grounding.vet(maybe, note: floated, now: now, calendar: calendar) == .drop("the note only wonders about it"))
        let dated = "She might do the marathon next Saturday."
        let hedgedButDated = Suggestion.followUp("Ask how the race went", due: day(9, 13), because: dated)
        #expect(review([hedgedButDated], note: dated).kept.count == 1)
        let event = Suggestion.fact("Interview", "Figma")
        #expect(Grounding.vet(event, note: "Her interview at Figma is next week.", now: now, calendar: calendar) == .drop("an event is not a fact"))
    }

    @Test("a label the model invented is not a kind of detail Tend keeps; a synonym is")
    func labels() {
        let note = "She's nervous about it, and off her feet for a couple of weeks. Her employer is Figma and her kids are called Lu and Sam."
        func vet(_ s: Suggestion) -> Grounding.Verdict { Grounding.vet(s, note: note, now: now, calendar: calendar) }
        #expect(vet(.fact("Nervous", "about it")) == .drop("not a kind of detail worth keeping"))
        #expect(vet(.fact("Mood", "nervous")) == .drop("a mood, plan or opinion is a guess, not a fact"))
        #expect(vet(.fact("Duration of recovery", "couple of weeks")) == .drop("not a kind of detail worth keeping"))
        if case .keep(let s) = vet(.fact("Employer", "Figma")) { #expect(s.title == "Works at") } else { Issue.record("employer") }
        if case .keep(let s) = vet(.fact("Children", "Lu and Sam")) { #expect(s.title == "Kids") } else { Issue.record("children") }
        if case .keep(let s) = vet(.fact("works at", "Figma")) { #expect(s.title == "Works at") } else { Issue.record("case") }
    }

    @Test("a question to the friend, or the sentence said back, becomes the occasion's own line; two on one occasion are one")
    func questionsAndRepeats() {
        let note = "Sam has knee surgery on Thursday. He'll be off his feet for a couple of weeks after."
        let question = Suggestion.followUp("When is the surgery?", due: day(9, 11), because: "Sam has knee surgery on Thursday.")
        #expect(review([question], note: note).kept.first?.title == "Check in after the surgery")
        let echo = Suggestion.followUp("Sam has knee surgery on Thursday", due: day(9, 11), because: "Sam has knee surgery on Thursday.")
        #expect(review([echo], note: note).kept.first?.title == "Check in after the surgery")
        let both = review([question, echo, .followUp("Check in after the surgery", due: day(9, 11), because: "Sam has knee surgery on Thursday.")], note: note)
        #expect(both.kept.count == 1)
        #expect(both.rejected.map(\.reason) == ["a repeat of another proposal", "a repeat of another proposal"])
    }

    @Test("a fact's value has to sit where the note says that kind of thing, about the friend")
    func labelCues() {
        let note = "Her interview at Figma is next Thursday. Dinner with Maya and Tom; Maya just got back from Peru. Her husband Marco just started at Anthropic. Tom's startup is launching next month. He's the best man at his brother's wedding next spring."
        func reason(_ s: Suggestion) -> String? {
            if case .drop(let why) = Grounding.vet(s, note: note, now: now, calendar: calendar) { return why }
            return nil
        }
        #expect(reason(.fact("Works at", "Figma")) == "the note doesn't say that about them")
        #expect(reason(.fact("Partner", "Maya")) == "the note doesn't say that about them")
        #expect(reason(.fact("Kids", "Tom")) == "the note doesn't say that about them")
        #expect(reason(.fact("Lives in", "Peru")) == "the note doesn't say that about them")
        #expect(reason(.fact("Works at", "Anthropic")) == "a detail about someone else in the note")
        #expect(reason(.fact("Works at", "next month")) == "a time, not a detail")
        #expect(reason(.fact("Lives in", "next spring")) == "a time, not a detail")
        #expect(reason(.fact("Partner", "Marco")) == nil)
        let stated = "Dev starts his new job at Stripe on Monday. She lives in Long Island City now. They got a puppy named Biscuit. She's at Meta and her kids are called Lu."
        let kept = review([.fact("Works at", "Stripe"), .fact("Lives in", "Long Island City"), .fact("Pets", "Biscuit")], note: stated).kept
        #expect(kept.count == 3)
        // The relative comes after the value: still hers — and still needs the note to say she works there.
        #expect(Grounding.vet(.fact("Works at", "Meta"), note: stated, now: now, calendar: calendar) == .drop("the note doesn't say that about them"))
        #expect(review([.fact("Works at", "Meta")], note: "She works at Meta and her kids are called Lu.").kept.count == 1)
    }

    @Test("a name-kind fact needs a name the note wrote as one, and a cue close to the value")
    func namesAndNearness() {
        let note = "She has a baby and two dogs. She's working with Sarah on the redesign. um we talked for like an hour and then we said we'd do dinner sometime. Her husband Marco is lovely."
        func reason(_ s: Suggestion) -> String? {
            if case .drop(let why) = Grounding.vet(s, note: note, now: now, calendar: calendar) { return why }
            return nil
        }
        #expect(reason(.fact("Kids", "two dogs")) == "a name is expected here, and the note gives none")
        #expect(reason(.fact("Works at", "redesign")) == "a name is expected here, and the note gives none")
        #expect(reason(.fact("Likes", "dinner")) == "the note doesn't say that about them")
        #expect(reason(.fact("Partner", "Marco")) == nil)
    }

    @Test("what the model actually did: phrases, occasions and nothing-in-particular as fact values")
    func modelFactShapes() {
        let note = "Big bar exam tomorrow. She's been studying nonstop. He mentioned nothing concrete about the company."
        func reason(_ s: Suggestion) -> String? {
            if case .drop(let why) = Grounding.vet(s, note: note, now: now, calendar: calendar) { return why }
            return nil
        }
        #expect(reason(.fact("Partner", "She's been studying nonstop.")) == "the value is a phrase from the note, not a name, place or thing")
        #expect(reason(.fact("Works at", "work is busy")) == "the value is a phrase from the note, not a name, place or thing")
        #expect(reason(.fact("Job", "bar exam")) == "an event is not a fact")
        #expect(reason(.fact("Job", "company")) == "the value names nothing in particular")
        #expect(reason(.fact("Job", "nothing concrete")) == "the value is a placeholder")
        let sound = "Their kids are called Lu and Sam. He's allergic to shellfish and peanuts."
        #expect(review([.fact("Kids", "Lu and Sam"), .fact("Allergy", "shellfish and peanuts")], note: sound).kept.count == 2)
    }

    @Test("a follow-up that repeats the note, or hangs on the note-writer's own Saturday, is dropped")
    func modelFollowUpShapes() {
        let ours = "Rescheduled our dinner to next Friday because her sitter cancelled."
        let echo = Suggestion.followUp(ours, due: day(9, 12), because: ours)
        #expect(Grounding.vet(echo, note: ours, now: now, calendar: calendar) == .drop("the note-writer is part of it"))
        let match = "We watched the match on Saturday and ordered too much pizza."
        let pizza = Suggestion.followUp("Did you order too much pizza?", due: day(9, 6), because: match)
        #expect(Grounding.vet(pizza, note: match, now: now, calendar: calendar) == .drop("the note-writer is part of it"))
        let hers = "Her interview at Figma is next week and she is nervous about it."
        let restated = Suggestion.followUp("Her interview at Figma is next week and she is nervous", due: day(9, 13), because: hers)
        #expect(review([restated], note: hers).kept.first?.title == "Ask how the interview went")
        let noEvent = "She's going to Lisbon next Saturday for a bit."
        let saidBack = Suggestion.followUp("She's going to Lisbon next Saturday for a bit", due: day(9, 13), because: noEvent)
        #expect(Grounding.vet(saidBack, note: noEvent, now: now, calendar: calendar) == .drop("the wording doesn't come from the note"))
        let lisbon = "She's going to Lisbon next Saturday."
        #expect(review([.followUp("Ask how Lisbon was", due: day(9, 13), because: lisbon)], note: lisbon).kept.count == 1)
    }

    // MARK: wording

    @Test("wording that strays from the note falls back to the event's own line, or is dropped when there is none")
    func wording() {
        let note = "Her interview at Figma is next week."
        let guess = Suggestion.followUp("Ask whether she got the job", due: day(9, 13), because: note)
        #expect(review([guess], note: note).kept.first?.title == "Ask how the interview went")
        let feelings = Suggestion.followUp("Ask how she is feeling about the interview", due: day(9, 13), because: note)
        #expect(review([feelings], note: note).kept.first?.title == "Ask how the interview went")
        let own = Suggestion.followUp("Ask how the Figma interview went", due: day(9, 13), because: note)
        #expect(review([own], note: note).kept.first?.title == "Ask how the Figma interview went")

        let trip = "She's going to Lisbon next Saturday."
        let fine = Suggestion.followUp("Ask how Lisbon was", due: day(9, 13), because: trip)
        #expect(review([fine], note: trip).kept.first?.title == "Ask how Lisbon was")
        let inferred = Suggestion.followUp("Ask how she felt about Lisbon", due: day(9, 13), because: trip)
        #expect(Grounding.vet(inferred, note: trip, now: now, calendar: calendar) == .drop("the wording doesn't come from the note"))
        let generic = Suggestion.followUp("Check in", due: day(9, 13), because: trip)
        #expect(Grounding.vet(generic, note: trip, now: now, calendar: calendar) == .drop("the wording doesn't come from the note"))
    }

    // MARK: facts

    @Test("a fact is made of the note's words")
    func factWords() {
        let note = "She's an engineer at Figma now and wants a pour-over kettle."
        #expect(review([.fact("Works at", "Figma")], note: note).kept.count == 1)
        #expect(review([.fact("Gift idea", "pour-over kettles")], note: note).kept.count == 1)
        let padded = Suggestion.fact("Role", "Software engineer at Figma")
        #expect(Grounding.vet(padded, note: note, now: now, calendar: calendar) == .drop("uses words the note doesn't: software"))
    }

    @Test("placeholders, moods, passages and echoes are not facts")
    func factShape() {
        let note = "Her husband Marco just started at Anthropic and she seemed happy about it."
        func reason(_ s: Suggestion) -> String? {
            if case .drop(let why) = Grounding.vet(s, note: note, now: now, calendar: calendar) { return why }
            return nil
        }
        #expect(reason(.fact("Kids", "none")) == "the value is a placeholder")
        #expect(reason(.fact("Partner", "not mentioned")) == "the value is a placeholder")
        #expect(reason(.fact("Feelings", "happy")) == "a mood, plan or opinion is a guess, not a fact")
        #expect(reason(.fact("Plans", "Anthropic")) == "a mood, plan or opinion is a guess, not a fact")
        #expect(reason(.fact("Partner", "Her husband Marco just started at Anthropic and she seemed happy")) == "the value is a passage, not a detail")
        #expect(reason(.fact("Partner", "partner")) == "the value repeats the label")
        #expect(reason(.fact("", "Marco")) == "the label is blank or too long")
        #expect(review([.fact("Partner", "Marco")], note: note).kept.count == 1)
    }

    @Test("the same proposal twice is one")
    func dedupe() {
        let note = "Her interview is next week. Her husband is Marco."
        let twice = [
            Suggestion.followUp("Ask how the interview went", due: day(9, 13), because: "Her interview is next week."),
            Suggestion.followUp("Ask how the interview went", due: day(9, 13), because: "Her interview is next week."),
            Suggestion.fact("Partner", "Marco"), Suggestion.fact("Partner", "Marco"),
        ]
        let out = review(twice, note: note)
        #expect(out.kept.count == 2)
        #expect(out.rejected.map(\.reason) == ["a repeat of another proposal", "a repeat of another proposal"])
    }

    // MARK: consistency

    @Test("everything the heuristic proposes passes the same rules unchanged")
    func heuristicAgrees() {
        let note = """
            Priya said her interview at Figma is next Thursday and she's nervous. Her husband Marco just started at Anthropic. \
            They moved to Oakland last month. Their daughter is called Lu. He's been wanting a pour-over kettle. \
            Got a puppy named Biscuit. Allergic to shellfish and peanuts. She's going to run a marathon soon.
            """
        let proposed = HeuristicExtractor(calendar: calendar).suggestions(for: note, now: now)
        #expect(proposed.count >= 7)
        let out = review(proposed, note: note)
        #expect(out.rejected.isEmpty)
        #expect(out.kept == proposed)
    }
}
