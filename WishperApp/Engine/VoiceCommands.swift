import Foundation

struct VoiceCommands {
    private static let replacements: [(pattern: String, replacement: String)] = [
        ("exclamation point", "!"),
        ("exclamation mark", "!"),
        ("question mark", "?"),
        ("full stop", "."),
        ("semicolon", ";"),
        ("em dash", " — "),
        ("ellipsis", "..."),
        ("open parenthesis", "("),
        ("close parenthesis", ")"),
        ("open quotes", "\""),
        ("close quotes", "\""),
        ("open quote", "\""),
        ("close quote", "\""),
        ("new paragraph", "\n\n"),
        ("new line", "\n"),
        ("newline", "\n"),
        ("period", "."),
        ("comma", ","),
        ("colon", ":"),
        ("dash", " — "),
        ("hyphen", "-"),
        ("tab", "\t"),
    ]
    
    static func process(_ text: String) -> String {
        var result = text
        
        // Apply replacements (case-insensitive, whole word)
        for (pattern, replacement) in replacements {
            let regex = try? NSRegularExpression(
                pattern: "\\b\(NSRegularExpression.escapedPattern(for: pattern))\\b",
                options: .caseInsensitive
            )
            if let regex {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: replacement
                )
            }
        }
        
        // Handle "capitalize" / "cap" — capitalize the next word
        let capPattern = try? NSRegularExpression(pattern: "\\b(capitalize|cap)\\s+(\\w)", options: .caseInsensitive)
        if let capPattern {
            while let match = capPattern.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) {
                let wordRange = Range(match.range(at: 2), in: result)!
                let letter = result[wordRange].uppercased()
                let fullRange = Range(match.range, in: result)!
                result.replaceSubrange(fullRange, with: letter)
            }
        }
        
        // Handle "delete that" / "scratch that" — remove previous sentence
        let deletePattern = try? NSRegularExpression(pattern: "[^.\\n]*\\b(delete that|scratch that)\\b", options: .caseInsensitive)
        if let deletePattern {
            result = deletePattern.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        
        // Clean up spacing around punctuation
        result = result.replacingOccurrences(of: "\\s+([,.;:?!])", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespaces)
        
        return result
    }
}
