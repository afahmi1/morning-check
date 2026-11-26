import Foundation

public enum Restedness: Int, Codable, CaseIterable, Sendable {
    case notAtAll = 1, slightly, somewhat, well, veryWell

    public var label: String {
        switch self {
        case .notAtAll: "Not at all rested"
        case .slightly: "Slightly rested"
        case .somewhat: "Somewhat rested"
        case .well: "Well rested"
        case .veryWell: "Very well rested"
        }
    }
}

public enum WakeDay {
    public static func key(_ date: Date, in zone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

public struct Rating: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case watch, phone }
    public let id: UUID
    public let value: Restedness
    public let reportedAt: Date
    public let timeZone: String
    public let wakeDay: String
    public let source: Source

    public init(_ value: Restedness, at date: Date = .now, zone: TimeZone = .current, source: Source) {
        id = UUID()
        self.value = value
        reportedAt = date
        timeZone = zone.identifier
        wakeDay = WakeDay.key(date, in: zone)
        self.source = source
    }

    public var isConsistent: Bool {
        guard let zone = TimeZone(identifier: timeZone), reportedAt.timeIntervalSince1970.isFinite,
              abs(reportedAt.timeIntervalSince1970) < 10_000_000_000 else { return false }
        return wakeDay == WakeDay.key(reportedAt, in: zone)
    }
}

public enum ScoreSource: String, Codable, Sendable {
    case manual, screenshot, notification

    public var label: String {
        switch self {
        case .manual: "Typed from Apple Health"
        case .screenshot: "Read from screenshot, confirmed by you"
        case .notification: "Read from alert text, confirmed by you"
        }
    }
}

public struct Score: Codable, Equatable, Sendable {
    public let value: Int
    public let source: ScoreSource

    public init?(_ value: Int, source: ScoreSource) {
        guard (0...100).contains(value) else { return nil }
        self.value = value
        self.source = source
    }

    public var isValid: Bool { (0...100).contains(value) }
}

public struct Morning: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public fileprivate(set) var rating: Rating?
    public fileprivate(set) var score: Score?
    public fileprivate(set) var candidate: Score?
}

public struct Diary: Codable, Equatable, Sendable {
    private var byDay: [String: Morning] = [:]
    public init() {}

    public var rows: [Morning] { byDay.values.sorted { $0.id > $1.id } }
    public subscript(_ day: String) -> Morning? { byDay[day] }

    // Keep the first independent report, even if a Watch transfer arrives later.
    @discardableResult
    public mutating func record(_ rating: Rating) -> Bool {
        guard rating.isConsistent else { return false }
        var row = byDay[rating.wakeDay] ?? Morning(id: rating.wakeDay)
        if let previous = row.rating {
            guard previous.reportedAt > rating.reportedAt ||
                    (previous.reportedAt == rating.reportedAt && previous.id.uuidString > rating.id.uuidString)
            else { return false }
        }
        row.rating = rating
        byDay[row.id] = row
        return true
    }

    @discardableResult
    public mutating func stage(_ candidate: Score, on day: String) -> Bool {
        guard candidate.isValid, candidate.source == .notification else { return false }
        var row = byDay[day] ?? Morning(id: day)
        guard row.score == nil else { return false }
        row.candidate = candidate
        byDay[day] = row
        return true
    }

    @discardableResult
    public mutating func confirm(_ score: Score, on day: String) -> Bool {
        guard score.isValid, var row = byDay[day], row.rating != nil else { return false }
        row.score = score
        row.candidate = nil
        byDay[day] = row
        return true
    }

    public mutating func clearScores(on day: String) {
        guard var row = byDay[day] else { return }
        row.score = nil
        row.candidate = nil
        byDay[day] = row.rating == nil ? nil : row
    }
}

public struct Pair: Equatable, Sendable {
    public let rating: Restedness
    public let score: Score

    public init(rating: Restedness, score: Score) {
        self.rating = rating
        self.score = score
    }
}

public struct Comparison: Sendable {
    public let pairs: [Pair]
    public let noScore: Int
    public let awaitingRating: Int
    public let highScore: Int
    public let highButNotRested: Int
    public let spearman: Double?

    public init(rows: [Morning]) {
        let pairs = rows.compactMap { row -> Pair? in
            guard let rating = row.rating, let score = row.score, score.isValid else { return nil }
            return Pair(rating: rating.value, score: score)
        }
        self.pairs = pairs
        noScore = rows.filter { $0.rating != nil && $0.score == nil }.count
        awaitingRating = rows.filter { $0.rating == nil && $0.candidate != nil }.count
        highScore = pairs.filter { $0.score.value >= 81 }.count
        highButNotRested = pairs.filter { $0.score.value >= 81 && $0.rating.rawValue <= 2 }.count
        spearman = Self.rankCorrelation(pairs)
    }

    public static func rankCorrelation(_ pairs: [Pair]) -> Double? {
        guard pairs.count >= 5 else { return nil }
        let x = ranks(pairs.map(\.score.value))
        let y = ranks(pairs.map(\.rating.rawValue))
        let mean = (Double(pairs.count) + 1) / 2
        var xy = 0.0, xx = 0.0, yy = 0.0
        for (a, b) in zip(x, y) {
            let dx = a - mean, dy = b - mean
            xy += dx * dy
            xx += dx * dx
            yy += dy * dy
        }
        guard xx > 0, yy > 0 else { return nil }
        return min(1, max(-1, xy / sqrt(xx * yy)))
    }

    private static func ranks(_ values: [Int]) -> [Double] {
        let indices = values.indices.sorted { values[$0] < values[$1] }
        var result = Array(repeating: 0.0, count: values.count)
        var start = 0
        while start < indices.count {
            var end = start + 1
            while end < indices.count && values[indices[end]] == values[indices[start]] { end += 1 }
            let average = (Double(start + 1) + Double(end)) / 2
            for index in indices[start..<end] { result[index] = average }
            start = end
        }
        return result
    }
}
