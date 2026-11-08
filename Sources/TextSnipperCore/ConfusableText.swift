import Foundation

public enum ConfusableText {
    private static let alphabet = "O0Il1S5"

    /// A short token made only of glyphs that OCR mixes up, such as `O0Il1S5`.
    public static func isolatedToken(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'` "))
        guard (4...12).contains(trimmed.count), trimmed.allSatisfy({ alphabet.contains($0) }) else {
            return nil
        }
        return trimmed
    }

    /// Confusable runs inside a longer line, such as the quotes in `let salt = "O0Il1S5"`.
    public static func embeddedTokens(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "[O0Il1S5]{4,12}") else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range)
        }
    }

    public static func differsOnlyByConfusables(_ lhs: String, _ rhs: String) -> Bool {
        guard lhs.count == rhs.count, lhs != rhs else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            left == right || sameGroup(left, right)
        }
    }

    /// Replaces one bounded token. A longer word that merely contains those letters is left alone.
    public static func replaceToken(_ token: String, or alternate: String, with choice: String, in text: String) -> String {
        for candidate in [token, alternate] where !candidate.isEmpty && candidate != choice {
            guard let range = boundedRange(of: candidate, in: text) else { continue }
            var copy = text
            copy.replaceSubrange(range, with: choice)
            return copy
        }
        return text
    }

    private static func boundedRange(of token: String, in text: String) -> Range<String.Index>? {
        var search = text.startIndex
        while let range = text.range(of: token, range: search..<text.endIndex) {
            let before = range.lowerBound == text.startIndex || !isWord(text[text.index(before: range.lowerBound)])
            let after = range.upperBound == text.endIndex || !isWord(text[range.upperBound])
            if before && after { return range }
            search = range.upperBound
        }
        return nil
    }

    private static func isWord(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    private static func sameGroup(_ lhs: Character, _ rhs: Character) -> Bool {
        let groups: [Set<Character>] = [
            ["O", "0"],
            ["I", "l", "1"],
            ["S", "5"],
        ]
        return groups.contains { $0.contains(lhs) && $0.contains(rhs) }
    }
}
