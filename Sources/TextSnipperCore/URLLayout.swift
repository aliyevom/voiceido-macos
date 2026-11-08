import Foundation

public enum URLLayout {
    /// Joins a URL that the screen wrapped onto the next line. Real list items stay separate.
    public static func joinWrappedLines(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var joined: [String] = []
        for line in lines {
            if let previous = joined.last, continuesURL(previous, line) {
                let head = previous.trimmingCharacters(in: .whitespaces)
                let tail = line.trimmingCharacters(in: .whitespaces)
                joined[joined.count - 1] = head + tail
            } else {
                joined.append(line)
            }
        }
        return joined.joined(separator: "\n")
    }

    private static func continuesURL(_ previous: String, _ next: String) -> Bool {
        let prev = previous.trimmingCharacters(in: .whitespaces)
        let nxt = next.trimmingCharacters(in: .whitespaces)
        guard !prev.isEmpty, !nxt.isEmpty, prev.contains("://") else { return false }
        if nxt.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil { return false }
        if nxt.contains(" "),
           !nxt.contains("="), !nxt.contains("%"), !nxt.contains("&"), !nxt.contains("[") {
            return false
        }
        if nxt.hasPrefix("&") || nxt.hasPrefix("%") || nxt.hasPrefix("]") { return true }
        if prev.last == "/" || prev.last == "[" || prev.last == "=" { return true }
        // A wrap can split a word, as in "&s" / "tart=...".
        let urlContinues = prev.contains("?") || prev.contains("&") || prev.contains("%")
            || nxt.contains("=") || nxt.contains("%") || nxt.contains("&")
        guard urlContinues, !nxt.contains(" ") else { return false }
        let prevContinues = prev.last?.isLetter == true || prev.last?.isNumber == true
        let nextContinues = nxt.first?.isLetter == true || nxt.first?.isNumber == true
        return prevContinues && nextContinues
    }
}
