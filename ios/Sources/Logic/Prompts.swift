// What the on-device model is told, as text the reader can change from
// Settings. Every line here exists because of a way the model went wrong:
// it filled every slot, guessed at feelings, took the note-writer's own
// plans for the friend's, and did calendar arithmetic it cannot do.

import Foundation

enum Prompts {
    static let extractor = """
        You read one short note a person wrote about a friend after talking to them. \
        Find the few things worth acting on, and leave everything else out. An empty answer is the right answer for most notes.

        A follow-up is for one specific event in the friend's own life that the note says is coming up or has just happened, \
        so the person can ask about it afterwards: an interview, a surgery, a trip, a move, an exam, a wedding, a launch. \
        Not for feelings, not for plans the note does not state, not for routine activities, and not for anything the note-writer \
        is doing themselves. Write the follow-up as one short imperative sentence using the note's own words.

        A fact is a durable detail about the friend that the note states outright: partner, kids, job, city, pet, allergy, \
        something they want. Not about other people the note mentions, not a mood, not a guess.

        Rules: copy the evidence sentence from the note word for word. Use only names, places and things the note itself names. \
        Never write "none", "unknown" or "N/A" — leave the item out instead. Leave the date empty unless the note names a day; \
        when it does, copy that day's YYYY-MM-DD from the calendar given.
        """

    static let judge = """
        You review proposals another assistant drew from one short note about a friend, and say which to keep. \
        Keep a proposal only if all of this holds: the evidence sentence really appears in the note; the note itself states \
        the event or the fact, with nothing read into it about feelings, reasons or plans; a follow-up is about something \
        the friend is doing, not the note-writer; the day matches what the note says; and it does not repeat another proposal. \
        Reject anything vague ("check in", "see how things are"), anything about the note-writer's own plans, and any fact \
        whose value uses words the note does not. Give one short reason for each rejection. \
        Be strict: leaving a proposal out costs nothing, and most notes deserve very few.
        """

    /// Reviews the judge may run on one note; each is a model call.
    static let defaultRounds = 2
    static let roundsRange = 1...4
}
