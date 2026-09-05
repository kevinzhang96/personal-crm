// Pasted lists, in the shapes people paste them.

import Testing
@testable import Tend

struct BulkNamesTests {
    @Test("one name per line, trimmed, blanks dropped")
    func lines() {
        #expect(BulkNames.parse("Ana Lu\n\n  Ben Ko  \nCy\n") == ["Ana Lu", "Ben Ko", "Cy"])
    }

    @Test("a single line splits on commas or semicolons")
    func oneLine() {
        #expect(BulkNames.parse("Ana, Ben;Cy") == ["Ana", "Ben", "Cy"])
        #expect(BulkNames.parse("Ana Lu, Ben\nCy") == ["Ana Lu, Ben", "Cy"], "only a lone line is split — multi-line input keeps its commas")
    }

    @Test("numbering and bullets are not names")
    func bullets() {
        #expect(BulkNames.parse("1. Ana\n2) Ben\n- Cy\n• Di\n* Ed") == ["Ana", "Ben", "Cy", "Di", "Ed"])
    }

    @Test("duplicates collapse to the first spelling")
    func duplicates() {
        #expect(BulkNames.parse("Ana\nana\nANA\nBen") == ["Ana", "Ben"])
    }

    @Test("nothing in, nothing out")
    func empty() {
        #expect(BulkNames.parse("").isEmpty)
        #expect(BulkNames.parse(" \n- \n").isEmpty)
    }
}
