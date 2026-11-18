import Foundation

/// Guesses whether text is code (or a path, JSON, a shell line…), so the
/// panel can set it in a monospaced font. A cheap scoring heuristic over the
/// start of the text; false negatives just mean proportional type.
enum CodeDetector {
    private static let sampleLength = 4000
    private static let threshold = 3

    static func looksLikeCode(_ text: String) -> Bool {
        let sample = String(text.prefix(sampleLength))
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: true)

        if lines.count == 1, isPath(trimmed) { return true }
        if isJSONLike(trimmed) { return true }

        var score = 0
        if lines.count > 1, lines.dropFirst().contains(where: { $0.hasPrefix("  ") || $0.hasPrefix("\t") }) {
            score += 2
        }
        let codeLineEndings = lines.filter { line in
            let end = line.trimmingCharacters(in: .whitespaces)
            return end.hasSuffix(";") || end.hasSuffix("{") || end.hasSuffix("}") || end.hasSuffix("};")
        }
        score += min(codeLineEndings.count, 2)

        let startsWithKeyword = lines.contains { line in
            let start = line.drop(while: \.isWhitespace)
            return keywords.contains { start.hasPrefix($0) }
        }
        if startsWithKeyword { score += 2 }

        let operatorCount = operators.filter { trimmed.contains($0) }.count
        score += min(operatorCount, 2)

        if hasCallSyntax(trimmed) { score += 1 }
        if looksLikeProse(trimmed) { score -= 2 }
        return score >= threshold
    }

    /// `/usr/local/bin`, `~/Documents/report.pdf`, `./build.sh`, `C:\Users`.
    private static func isPath(_ text: String) -> Bool {
        guard text.count > 1, text.count <= 1024, !text.contains("  ") else { return false }
        if ["~/", "./", "../"].contains(where: text.hasPrefix) { return true }
        if text.hasPrefix("/") {
            // "/usr" or "/Users/me/My File.pdf", but not "/ a slash in prose".
            return text.dropFirst().contains("/") || !text.contains(" ")
        }
        let scalars = Array(text.unicodeScalars.prefix(3))
        return scalars.count == 3 && scalars[0].properties.isAlphabetic && scalars[1] == ":" && scalars[2] == "\\"
    }

    private static func isJSONLike(_ text: String) -> Bool {
        let pairs: [(Character, Character)] = [("{", "}"), ("[", "]")]
        return pairs.contains { open, close in
            text.first == open && text.last == close && text.contains(":") && text.contains("\"")
        }
    }

    /// An identifier immediately followed by `(`, as in `print(x)`.
    private static func hasCallSyntax(_ text: String) -> Bool {
        var previous: Character?
        for character in text {
            if character == "(", let previous, previous.isLetter || previous.isNumber || previous == "_" {
                return text.contains(")")
            }
            previous = character
        }
        return false
    }

    /// Sentences: mostly words and spaces, ending in sentence punctuation.
    private static func looksLikeProse(_ text: String) -> Bool {
        guard let last = text.last, ".!?".contains(last) else { return false }
        let wordish = text.filter { $0.isLetter || $0 == " " || $0 == "," || $0 == "'" }.count
        return Double(wordish) / Double(text.count) > 0.85
    }

    private static let keywords = [
        "func ", "def ", "class ", "import ", "return ", "let ", "var ", "const ", "struct ",
        "enum ", "fn ", "package ", "public ", "private ", "#include", "#import", "#!/",
        "if (", "for (", "while (", "} else", "SELECT ", "select ", "using ", "namespace ",
        "export ", "function ", "async ", "$ ", "sudo ", "git ", "npm ", "brew ",
    ]

    private static let operators = [
        "=>", "->", "==", "!=", "&&", "||", "::", "+=", "</", "/>", "();", "${", "\\n",
    ]
}
