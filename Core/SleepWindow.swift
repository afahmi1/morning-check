import Foundation

public struct SleepInterval: Sendable {
    public let start: Date
    public let end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }
}

public enum SleepWindow {
    // Input is exclusively asleep intervals, prefiltered to Apple Watch provenance.
    // A prompt candidate is an inferred session, not a real-time wake event.
    public static func qualifyingEnd(in intervals: [SleepInterval], now: Date) -> Date? {
        let ordered = intervals.filter { $0.start < $0.end && $0.end <= now &&
            $0.start >= now.addingTimeInterval(-36 * 3600) }.sorted { $0.start < $1.start }
        var end: Date?
        var asleep: TimeInterval = 0
        var latestQualified: Date?
        for interval in ordered {
            if let previous = end, interval.start.timeIntervalSince(previous) <= 45 * 60 {
                if interval.end > previous {
                    asleep += interval.end.timeIntervalSince(max(previous, interval.start))
                    end = interval.end
                }
            } else {
                if asleep >= 3 * 3600 { latestQualified = end }
                asleep = interval.end.timeIntervalSince(interval.start)
                end = interval.end
            }
        }
        if asleep >= 3 * 3600 { latestQualified = end }
        guard let finish = latestQualified, now.timeIntervalSince(finish) <= 2 * 3600 else { return nil }
        return finish
    }
}
