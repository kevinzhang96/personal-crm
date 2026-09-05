// The search language, on the people it is meant to find.

import Testing
@testable import Tend

struct PeopleQueryTests {
    let priya = SearchableFriend(
        name: "Priya Nasir", nickname: "Pri", tags: ["college", "climbing"], location: "Long Island City, NY",
        howWeMet: "Sam's party", groups: ["Close", "College"],
        facts: [.init(label: "Works at", value: "Figma"), .init(label: "Partner", value: "Marco"), .init(label: "Gift idea", value: "pour-over kettle")],
        notes: ["Her interview at Figma is next Thursday", "Wants to go skiing in Feb"], starred: true)
    let sam = SearchableFriend(name: "Sam Okafor", tags: ["work"], location: "Brooklyn", groups: ["Friends"],
                               facts: [.init(label: "Lives in", value: "LIC")], notes: ["Moved to LIC"])

    func q(_ s: String) -> PeopleQuery { PeopleQuery.parse(s) }

    @Test("bare words hit any field, case- and accent-insensitively")
    func words() {
        #expect(q("nasir").matches(priya))
        #expect(q("pri").matches(priya))
        #expect(q("kettle").matches(priya), "facts count")
        #expect(q("skiing").matches(priya), "notes count")
        #expect(q("brooklyn").matches(sam))
        #expect(!q("brooklyn").matches(priya))
        #expect(q("FIGMA").matches(priya))
    }

    @Test("lives: reads the location and a Lives-in fact")
    func lives() {
        #expect(q("lives:lic").matches(sam), "from the fact")
        #expect(q("lives:island").matches(priya), "from the location")
        #expect(!q("lives:lic").matches(priya), "'LIC' is not in 'Long Island City' as text")
        #expect(q("lives:\"long island\"").matches(priya), "quoted phrase")
    }

    @Test("tags: #tag and tag:, groups, met, name, notes, star")
    func scopes() {
        #expect(q("#climb").matches(priya))
        #expect(q("tag:college").matches(priya))
        #expect(!q("#college").matches(sam))
        #expect(q("tag:").matches(sam), "bare tag: means has any tag")
        #expect(q("group:close").matches(priya))
        #expect(q("in:friends").matches(sam))
        #expect(q("met:party").matches(priya))
        #expect(q("name:okafor").matches(sam))
        #expect(!q("name:figma").matches(priya), "name: does not read facts")
        #expect(q("note:skiing").matches(priya))
        #expect(q("star:").matches(priya))
        #expect(!q("starred:yes").matches(sam))
        #expect(q("starred:no").matches(sam))
    }

    @Test("any other key is a fact label; an empty value means the fact exists")
    func facts() {
        #expect(q("works:figma").matches(priya))
        #expect(q("partner:").matches(priya))
        #expect(!q("partner:").matches(sam))
        #expect(q("gift:kettle").matches(priya))
        #expect(!q("works:google").matches(priya))
    }

    @Test("terms AND together, and an empty query matches everyone")
    func combination() {
        #expect(q("#college works:figma").matches(priya))
        #expect(!q("#college lives:brooklyn").matches(priya))
        #expect(q("").isEmpty)
        #expect(q("   ").isEmpty)
        #expect(q("nasir").needsNotes)
        #expect(!q("works:figma").needsNotes)
        #expect(q("note:x").needsNotes)
    }
}
