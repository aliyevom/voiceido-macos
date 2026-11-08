import Foundation

public enum HealGate {
    /// Sentences and code both go to the vision model.
    /// A tiny drag stays local so the clipboard returns immediately.
    public static func shouldConsult(_ draft: String, codeCapture: Bool) -> Bool {
        _ = codeCapture
        return draft.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
    }
}
