import Foundation

/// This is a copy from explicitly supplied alert inputs, not access to Apple's score in HealthKit.
public enum AlertScoreInput: Equatable, Sendable {
    case noText, noTimestamp, stale, noUnambiguousScore
    case candidate(Score, day: String)

    public static func evaluate(text: String?, receivedAt: Date?, now: Date, zone: TimeZone = .current) -> Self {
        guard let text, !text.isEmpty else { return .noText }
        guard let receivedAt else { return .noTimestamp }
        guard let day = PromptPolicy.eligibleDay(for: .appleAlert, signalAt: receivedAt, now: now, zone: zone) else { return .stale }
        guard let value = ScoreText.candidate(text), let score = Score(value, source: .notification) else { return .noUnambiguousScore }
        return .candidate(score, day: day)
    }
}
