import Foundation
import XCTest
@testable import MorningCheckCore

final class CoreTests: XCTestCase {
    // Tests exercise domain boundaries and in-memory control flow only. No journal data.
    func testWholeNumbersOnly() {
        for x in [0, 1, 99, 100] { XCTAssertEqual(ScoreText.manual(String(x)), x) }
        for x in ["", "101", "-1", "1.0", "100/100", "1e2"] { XCTAssertNil(ScoreText.manual(x)) }
    }

    func testTextRequiresUnambiguousSleepScoreContext() {
        for boundary in [0, 100] {
            XCTAssertEqual(ScoreText.candidate("Sleep Score: \(boundary)"), boundary)
            XCTAssertEqual(ScoreText.candidate("Sleep Score\n\(boundary)/100"), boundary)
            XCTAssertEqual(ScoreText.candidate("Your sleep score was \(boundary)/100."), boundary)
            XCTAssertEqual(ScoreText.candidate("Your sleep score is \(boundary)."), boundary)
        }
        for bad in ["Steps: 100/100", "Sleep Score: 101", "Sleep Score: 0.5", "Sleep Score: -1",
                    "Sleep Score: 12:00", "Sleep Score: 50/50", "Sleep Score 7 h", "Sleep Score: 0\nSleep Score: 100"] {
            XCTAssertNil(ScoreText.candidate(bad), bad)
        }
    }

    func testCandidateRequiresIndependentRatingAndConfirmation() throws {
        let now = Date.now
        let day = WakeDay.key(now)
        let candidate = try XCTUnwrap(Score(100, source: .notification))
        var diary = Diary()
        XCTAssertTrue(diary.stage(candidate, on: day))
        XCTAssertNil(diary[day]?.score)
        XCTAssertFalse(diary.confirm(candidate, on: day))
        XCTAssertEqual(Comparison(rows: diary.rows).awaitingRating, 1)
        XCTAssertTrue(diary.record(Rating(.notAtAll, at: now, source: .watch)))
        XCTAssertEqual(Comparison(rows: diary.rows).noScore, 1)
        XCTAssertTrue(diary.confirm(candidate, on: day))
        XCTAssertEqual(Comparison(rows: diary.rows).highButNotRested, 1)
        XCTAssertNil(diary[day]?.candidate)
        diary.clearScores(on: day)
        XCTAssertNil(diary[day]?.score)
        XCTAssertNotNil(diary[day]?.rating)
    }

    func testEarlierWatchRatingWinsOverLaterPhoneEntry() throws {
        let now = Date.now
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let base = calendar.startOfDay(for: now).addingTimeInterval(3600)
        let early = Rating(.somewhat, at: base, zone: zone, source: .watch)
        let late = Rating(.well, at: base.addingTimeInterval(60), zone: zone, source: .phone)
        var diary = Diary()
        XCTAssertTrue(diary.record(late))
        XCTAssertTrue(diary.record(early))
        XCTAssertFalse(diary.record(early))
        XCTAssertFalse(diary.record(late))
        let roundTrip = try JSONDecoder().decode(Diary.self, from: JSONEncoder().encode(diary))
        XCTAssertEqual(roundTrip[early.wakeDay]?.rating, early)
    }

    func testTieAwareRanksAndNoConstantSeriesCorrelation() {
        let levels: [Restedness] = [.notAtAll, .notAtAll, .somewhat, .well, .veryWell]
        let ordered = levels.compactMap { level in Score(level.rawValue, source: .manual).map { Pair(rating: level, score: $0) } }
        XCTAssertEqual(Comparison.rankCorrelation(ordered), 1)
        let reverse = levels.compactMap { level in Score(100 - level.rawValue, source: .manual).map { Pair(rating: level, score: $0) } }
        XCTAssertEqual(Comparison.rankCorrelation(reverse), -1)
        XCTAssertNil(Comparison.rankCorrelation(Array(ordered.prefix(4))))
        XCTAssertNil(Comparison.rankCorrelation(Array(repeating: ordered[0], count: 5)))
    }

    func testSleepGateSkipsShortAndStaleDataAndMergesOverlap() {
        let now = Date.now
        func interval(_ start: Double, _ end: Double) -> SleepInterval {
            SleepInterval(start: now.addingTimeInterval(start * 3600), end: now.addingTimeInterval(end * 3600))
        }
        XCTAssertNil(SleepWindow.qualifyingEnd(in: [], now: now))
        XCTAssertNil(SleepWindow.qualifyingEnd(in: [interval(-8, -3)], now: now))
        XCTAssertNil(SleepWindow.qualifyingEnd(in: [interval(-2, -1), interval(-2, -1), interval(-1.5, 0)], now: now))
        XCTAssertEqual(SleepWindow.qualifyingEnd(in: [interval(-5, -1.5), interval(-3, -1)], now: now), now.addingTimeInterval(-3600))
    }
}
