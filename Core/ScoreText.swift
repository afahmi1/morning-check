import Foundation

public enum ScoreText {
    private static let label = #"^(?:your\s+)?(?:apple(?:['’]s)?\s+)?sleep\s+score\b"#
    private static let heading = label + #"\s*:?$"#
    // Match the whole score field; do not take a valid-looking prefix of a range, fraction or date.
    private static let value = #"([0-9]{1,3})(?:\s*/\s*100)?(?:\s+(?:points?|very\s+low|low|ok|high|very\s+high))?[.!]?"#
    private static let standalone = "^" + value + "$"
    private static let inline = label + #"\s*(?:(?:is|was|of)\b\s*)?[:=]?\s*"# + value + "$"

    public static func manual(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.utf8.count <= 3, s.utf8.allSatisfy({ (48...57).contains($0) }),
              let value = Int(s), (0...100).contains(value) else { return nil }
        return value
    }

    // Only propose a number with Sleep Score context. Never silently save it.
    public static func candidate(_ raw: String) -> Int? {
        guard !raw.isEmpty, raw.utf8.count <= 12_000 else { return nil }
        let lines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var candidates = Set<Int>()
        for i in lines.indices where lines[i].range(of: label, options: [.regularExpression, .caseInsensitive]) != nil {
            let line = lines[i]
            let direct = matches(inline, line)
            if !direct.isEmpty { candidates.formUnion(direct); continue }
            // Apple’s detail card can place the score immediately below a standalone heading.
            guard line.range(of: heading, options: [.regularExpression, .caseInsensitive]) != nil,
                  let adjacent = lines.dropFirst(i + 1).first else { return nil }
            let separate = matches(standalone, adjacent)
            guard !separate.isEmpty else { return nil }
            candidates.formUnion(separate)
        }
        guard candidates.count == 1, let value = candidates.first, (0...100).contains(value) else { return nil }
        return value
    }

    /// English notification prose, guarded by a matching Health source and score-band title.
    /// Require exactly one numerical field, a known score phrase, and a complete integer boundary.
    public static func alertBody(_ raw: String) -> Int? {
        guard !raw.isEmpty, raw.utf8.count <= 12_000,
              let digits = try? NSRegularExpression(pattern: #"\p{N}+"#) else { return nil }
        let range = NSRange(raw.startIndex..., in: raw)
        let fields = digits.matches(in: raw, range: range)
        if let structured = candidate(raw) ?? candidate("Sleep Score\n" + raw) {
            if fields.count == 1 { return structured }
            if fields.count == 2,
               let fraction = try? NSRegularExpression(pattern: #"([0-9]{1,3})\s*/\s*100"#),
               let match = fraction.firstMatch(in: raw, range: range),
               match.range(at: 1) == fields[0].range,
               let field = Range(match.range(at: 1), in: raw), manual(String(raw[field])) == structured {
                return structured
            }
            return nil
        }
        guard fields.count == 1 else { return nil }
        let phrases = #"(?:you\s+(?:scored|earned|got)|score\s+(?:of|(?:down\s+)?to|was)|sleep\s+score\s+last\s+night\s+was|helped\s+you\s+(?:score|earn)|and\s+(?:scored|earned)|led\s+to|added\s+up\s+to|gave\s+you|earning|earned\s+you|that['’]s|sleep\s+session\s+with|night['’]s\s+sleep\s+with)"#
        let pattern = #"\b"# + phrases + #"\s+([0-9]{1,3})(?=\s+(?:last\s+night\b|for\s+the\s+night\b|due\s+to\b|means\b)|[.!?,]|$)"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: raw, range: range), match.range(at: 1) == fields[0].range,
              let field = Range(match.range(at: 1), in: raw) else { return nil }
        return manual(String(raw[field]))
    }

    private static func matches(_ pattern: String, _ string: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: string, range: NSRange(string.startIndex..., in: string)).compactMap {
            guard let range = Range($0.range(at: 1), in: string) else { return nil }
            return Int(string[range])
        }
    }
}
