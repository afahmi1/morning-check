import Foundation

public struct SleepInterval: Sendable {
    public let start: Date
    public let end: Date
    /// Nil is asleep with no specified stage. Do not pass Awake or In Bed intervals.
    public let stage: SleepStage?

    public init(start: Date, end: Date, stage: SleepStage? = nil) {
        self.start = start
        self.end = end
        self.stage = stage
    }
}

public enum SleepWindow {
    public static let lookback: TimeInterval = 36 * 3600
    fileprivate static let maximumRatingDelay: TimeInterval = 4 * 3600
    private static let maximumSessionGap: TimeInterval = 45 * 60
    private static let minimumPromptAsleep: TimeInterval = 3 * 3600
    private static let minimumStageAsleep: TimeInterval = 3600

    // These are saved, Watch-only asleep samples, not live wake events.
    public static func qualifyingEnd(in intervals: [SleepInterval], now: Date) -> Date? {
        let night = sessions(in: intervals, endingBy: now).last { $0.asleep >= minimumPromptAsleep }
        guard let end = night?.end, now.timeIntervalSince(end) <= 2 * 3600 else { return nil }
        return end
    }

    /// Most recent qualifying sleep before the check-in, in the rating's recorded time zone.
    /// Use the stage at the end of the session, never an earlier known band as a fallback.
    public static func wakeStage(in intervals: [SleepInterval], for rating: Rating) -> WakeStage? {
        guard rating.isConsistent,
              !intervals.contains(where: { $0.start <= rating.reportedAt && $0.end > rating.reportedAt }),
              let night = sessions(in: intervals, endingBy: rating.reportedAt).last(where: { $0.asleep >= minimumStageAsleep }),
              night.terminalStages.count == 1, let stage = night.terminalStages.first else { return nil }
        let reading = WakeStage(stage: stage, endedAt: night.end)
        return reading.matches(rating) ? reading : nil
    }

    private struct Session {
        var end: Date
        var asleep: TimeInterval
        var terminalStages: Set<SleepStage>

        init(_ band: SleepInterval) {
            end = band.end
            asleep = band.end.timeIntervalSince(band.start)
            terminalStages = band.stage.map { [$0] } ?? []
        }

        mutating func extend(with band: SleepInterval) {
            if band.end > end {
                asleep += band.end.timeIntervalSince(max(end, band.start))
                end = band.end
                terminalStages = band.stage.map { [$0] } ?? []
            } else if band.end == end, let stage = band.stage {
                terminalStages.insert(stage)
            }
        }
    }

    private static func sessions(in intervals: [SleepInterval], endingBy cutoff: Date) -> [Session] {
        let ordered = intervals.filter {
            $0.start >= cutoff.addingTimeInterval(-lookback) && $0.start < $0.end && $0.end <= cutoff
        }.sorted { $0.start < $1.start }
        var result: [Session] = []
        for band in ordered {
            if let last = result.indices.last, band.start.timeIntervalSince(result[last].end) <= maximumSessionGap {
                result[last].extend(with: band)
            } else {
                result.append(Session(band))
            }
        }
        return result
    }
}

public enum SleepStage: String, Codable, CaseIterable, Sendable {
    case core, deep, rem

    public var label: String {
        switch self {
        case .core: "Core"
        case .deep: "Deep"
        case .rem: "REM"
        }
    }
}

public struct WakeStage: Codable, Equatable, Sendable {
    public let stage: SleepStage
    public let endedAt: Date

    fileprivate init(stage: SleepStage, endedAt: Date) {
        self.stage = stage
        self.endedAt = endedAt
    }

    public func matches(_ rating: Rating) -> Bool {
        guard let zone = TimeZone(identifier: rating.timeZone),
              (0...SleepWindow.maximumRatingDelay).contains(rating.reportedAt.timeIntervalSince(endedAt)) else { return false }
        return WakeDay.key(endedAt, in: zone) == rating.wakeDay
    }
}

public struct WakeStageComparison: Sendable {
    public struct Group: Identifiable, Sendable {
        public let stage: SleepStage
        public let count: Int
        public let medianRestedness: Double
        public let scoreCount: Int
        public let medianScore: Double?
        public var id: SleepStage { stage }
    }

    public let groups: [Group]
    public let matched: Int
    public let missing: Int

    public init(rows: [Morning]) {
        let rated = rows.compactMap { row in row.rating.map { (row: row, rating: $0) } }
        let paired = rated.compactMap { item -> (stage: SleepStage, rested: Int, score: Int?)? in
            guard let wake = item.row.wakeStage, wake.matches(item.rating) else { return nil }
            let score = item.row.score.flatMap { $0.isValid ? $0.value : nil }
            return (wake.stage, item.rating.value.rawValue, score)
        }
        let byStage = Dictionary(grouping: paired, by: \.stage)
        groups = SleepStage.allCases.compactMap { stage in
            guard let values = byStage[stage], let rest = Self.median(values.map(\.rested)) else { return nil }
            let scores = values.compactMap(\.score)
            return Group(stage: stage, count: values.count, medianRestedness: rest, scoreCount: scores.count,
                         medianScore: Self.median(scores))
        }
        matched = paired.count
        missing = rated.count - matched
    }

    private static func median(_ values: [Int]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (Double(sorted[middle - 1]) + Double(sorted[middle])) / 2 : Double(sorted[middle])
    }
}
