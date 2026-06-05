import Foundation

/// Filtrado local de lenguaje objetable en mensajes de chat (Guideline 1.2).
enum ContentModerationFilter {
    /// Versión de términos mostrada en registro / inicio de sesión.
    static let currentTermsVersion = "2026-06-05"

    private static let blockedTerms: [String] = [
        "puta", "puto", "mierda", "cabron", "cabrón", "joder", "coño", "cono",
        "maricon", "maricón", "subnormal", "imbecil", "imbécil", "idiota",
        "fuck", "fucking", "shit", "bitch", "asshole", "cunt", "nigger", "nazi",
        "pedo", "porn", "porno", "xxx", "kill yourself", "suicid",
    ]

    /// `true` si el texto contiene términos prohibidos (bloquea envío).
    static func containsObjectionableContent(_ text: String) -> Bool {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return false }
        return blockedTerms.contains { term in
            normalized.contains(normalize(term))
        }
    }

    /// Sustituye términos prohibidos por asteriscos al mostrar mensajes entrantes.
    static func sanitizeForDisplay(_ text: String) -> String {
        var result = text
        for term in blockedTerms {
            result = replace(term: term, in: result)
        }
        return result
    }

    private static func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(term: String, in text: String) -> String {
        let pattern = #"(?i)\b"# + NSRegularExpression.escapedPattern(for: term) + #"\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let mask = String(repeating: "•", count: max(3, term.count))
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: mask)
    }
}
