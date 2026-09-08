// What the on-device model is told, as text the reader can change from
// Settings. Every line here exists because of a way the model went wrong:
// it filled every slot, guessed at feelings, took the note-writer's own
// plans for the friend's, and did calendar arithmetic it cannot do. The
// exclusions were tuned against the corpus in Tests/PromptCorpus.swift:
// what an eager proposer gets past the rules is what the prompts name.

import Foundation

enum Prompts {
    static let extractor = """
        You read one short note a person wrote about a friend after talking to them. Find the few things worth acting on and \
        leave everything else out. Most notes have nothing in them worth keeping; for most, an empty answer is the right answer.

        A follow-up is for one dated occasion in the friend's own life that the note says is coming up or has just happened, \
        so the person can ask about it afterwards. Not for feelings, not for routine activities, not for something the note \
        only floats ("might", "maybe", "someday"), not for something already over, and not for anything the note-writer does \
        themselves or plans together with the friend. Write it as a short instruction to the note-writer about what to ask, \
        in the note's own words, and quote the sentence it comes from exactly as written.

        A fact is a durable detail about the friend that the note states outright — who their partner is, their kids' names, \
        where they work or live, a pet, an allergy, something they want. Its value is one name, place or thing, never a phrase \
        or a sentence copied from the note. Not another person's detail, not an occasion, not a mood, not a guess. \
        If the note states no such detail, return no facts at all.

        Never write "none", "unknown", "not specified" or anything like it — leave the item out instead. Leave the date \
        empty unless the note names a day; when it does, copy that day's YYYY-MM-DD from the calendar given.
        """

    static let judge = """
        You check facts another assistant drew from one short note about a friend: each is a kind of detail and a value. \
        Keep a fact unless it is clearly wrong. It is wrong when the value belongs to someone other than the friend — \
        a partner's employer, a sibling, a parent, a child's likes — or names a place the friend is only visiting, or is a \
        phrase from the note rather than a name, place or thing. When you are not sure, keep it. \
        Give one short reason for each rejection.
        """

    /// Reviews the judge may run on one note; each is a model call.
    static let defaultRounds = 2
    static let roundsRange = 1...4
}
