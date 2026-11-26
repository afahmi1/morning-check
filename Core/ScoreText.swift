import Foundation

public enum ScoreText {
    private static let label = #"\bsleep\s+score\b"#
    private static let standalone = #"^([0-9]{1,3})\s*(?:/\s*100)?$"#
    private static let inline = #"\bsleep\s+score\s*(?:is\s+|was\s+|of\s+)?[:=]?\s*([0-9]{1,3})(?![0-9A-Za-z:/%-]|[.,][0-9])(?!\s*(?:h\b|hours?\b|minutes?\b|mins?\b|%))(?:\s*/\s*100\b|(?!\s*/))"#
    private static let fraction = #"(?<![\d.-])\b([0-9]{1,3})\s*/\s*100\b"#

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
            candidates.formUnion(matches(inline, line))
            candidates.formUnion(matches(fraction, line))
            // Apple’s detail card can place the score immediately below the label.
            if line.range(of: #"^sleep\s+score\s*:?$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                for adjacent in lines.dropFirst(i + 1).prefix(2) {
                    candidates.formUnion(matches(standalone, adjacent))
                }
            }
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
