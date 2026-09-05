// A pasted list of people, as names. One per line is the shape; a single
// line separated by commas or semicolons is accepted too, and the
// numbering and bullets a list arrives with are not part of anyone's name.

import Foundation

enum BulkNames {
    static func parse(_ text: String) -> [String] {
        var lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count == 1, lines[0].contains(where: { $0 == "," || $0 == ";" }) {
            lines = lines[0].split(whereSeparator: { $0 == "," || $0 == ";" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        var seen = Set<String>()
        return lines.compactMap { line in
            let name = strip(line)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { return nil }
            return name
        }
    }

    /// "1. Ana", "2) Ben", "- Cy", "• Di", "* Ed" are Ana, Ben, Cy, Di, Ed.
    private static func strip(_ line: String) -> String {
        line.replacingOccurrences(of: "^(\\d+[.)]|[-•*])\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
