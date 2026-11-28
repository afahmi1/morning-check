import Foundation

/// An explicit copy from a user-configured Shortcuts notification, never a HealthKit read.
public enum AutomaticScoreInput: Equatable, Sendable {
    case sourceMismatch, missingTimestamp, stale, noScore
    case score(Score, day: String)

    public static func evaluate(text: String?, title: String?, sourceApp: String?, receivedAt: Date?, now: Date, zone: TimeZone = .current) -> Self {
        let source = sourceApp?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard source == "health" || source == "com.apple.health",
              let title = title?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let band = bands[title] else { return .sourceMismatch }
        guard let receivedAt else { return .missingTimestamp }
        guard receivedAt <= now,
              let day = PromptPolicy.eligibleDay(for: .appleAlert, signalAt: receivedAt, now: now, zone: zone) else { return .stale }
        guard let text, text.utf8.count <= 12_000,
              let number = ScoreText.alertBody(text),
              band.contains(number), let score = Score(number, source: .automaticNotification) else { return .noScore }
        return .score(score, day: day)
    }

    // English Apple notification titles and current score bands; abstain on unknown formats.
    private static let bands: [String: ClosedRange<Int>] = [
        "very low sleep score": 0...40,
        "low sleep score": 41...60,
        "ok sleep score": 61...80,
        "high sleep score": 81...95,
        "very high sleep score": 96...100
    ]
}
