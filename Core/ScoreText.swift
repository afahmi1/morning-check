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

    private static func matches(_ pattern: String, _ string: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: string, range: NSRange(string.startIndex..., in: string)).compactMap {
            guard let range = Range($0.range(at: 1), in: string) else { return nil }
            return Int(string[range])
        }
    }
}
