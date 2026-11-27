import Foundation
import XCTest
@testable import MorningCheckCore

final class WakeStageTests: XCTestCase {
    // Hypothetical interval and rating fixtures. Only exercised in memory; no Health or diary data.
    private let zone = TimeZone(identifier: "America/Los_Angeles")!
    private let time = ISO8601DateFormatter().date(from: "2026-03-08T15:00:00Z")!

    private func band(_ from: Double, _ through: Double, _ stage: SleepStage?) -> SleepInterval {
        SleepInterval(start: time.addingTimeInterval(from * 3600), end: time.addingTimeInterval(through * 3600), stage: stage)
    }

    private func rating(_ value: Restedness = .somewhat, atHour offset: Double = 0) -> Rating {
        Rating(value, at: time.addingTimeInterval(offset * 3600), zone: zone, source: .watch)
    }

    func testEndsOnWakeDateUsingRatingTimeZoneAndIgnoresLaterNap() throws {
        let night = [band(-8, -3, .deep), band(-3, -0.6, .core), band(-0.6, -0.1, .rem)]
        let result = try XCTUnwrap(SleepWindow.wakeStage(in: Array(night.reversed()) + [band(4, 5, .core)], for: rating()))
        XCTAssertEqual(result.stage, .rem)
        XCTAssertEqual(result.endedAt, time.addingTimeInterval(-360))
        XCTAssertTrue(result.matches(rating()))
        XCTAssertNil(SleepWindow.wakeStage(in: [band(-13, -9, .rem)], for: rating()))
    }

    func testAbstainsOnUnknownOrConflictingTerminalStage() {
        let earlier = band(-7, -1.5, .core)
        XCTAssertNil(SleepWindow.wakeStage(in: [earlier, band(-1.5, -0.1, nil)], for: rating()))
        XCTAssertNil(SleepWindow.wakeStage(in: [earlier, band(-1.5, -0.1, .deep), band(-0.8, -0.1, .rem)], for: rating()))
        let ending = band(-1.5, -0.1, .rem)
        XCTAssertEqual(SleepWindow.wakeStage(in: [earlier, ending, ending, band(-7, -0.1, nil)], for: rating())?.stage, .rem)
    }

    func testUnspecifiedFinalMinuteAndBriefOrStaleSleepAreNotFilledIn() {
        XCTAssertNil(SleepWindow.wakeStage(in: [band(-7, -0.2, .rem), band(-0.2, -0.1, nil)], for: rating()))
        XCTAssertNil(SleepWindow.wakeStage(in: [band(-0.75, 0, .core), band(-0.75, 0, .core)], for: rating()))
        XCTAssertNil(SleepWindow.wakeStage(in: [band(-8, -4.01, .deep)], for: rating()))
        XCTAssertNil(SleepWindow.wakeStage(in: [band(-6, -1, .deep), band(-0.2, 0.2, .core)], for: rating()))
        XCTAssertEqual(SleepWindow.wakeStage(in: [band(-7, -2, .deep), band(-0.5, -0.25, .core)], for: rating())?.stage, .deep)
    }

    func testStoredStageIsNotAttachedToReplacedRatingAndSurvivesClearingScores() throws {
        let later = rating(atHour: 1)
        let earlier = rating()
        let bands = [band(-6, -0.2, .rem)]
        let stage = try XCTUnwrap(SleepWindow.wakeStage(in: bands, for: later))
        var diary = Diary()
        XCTAssertFalse(diary.attach(stage, to: later))
        XCTAssertTrue(diary.record(later))
        XCTAssertTrue(diary.attach(stage, to: later))
        XCTAssertFalse(diary.attach(stage, to: later))
        XCTAssertTrue(diary.record(earlier))
        XCTAssertNil(diary[later.wakeDay]?.wakeStage)
        XCTAssertFalse(diary.attach(stage, to: later))
        XCTAssertTrue(diary.attach(stage, to: earlier))
        diary.clearScores(on: earlier.wakeDay)
        let restored = try JSONDecoder().decode(Diary.self, from: JSONEncoder().encode(diary))
        XCTAssertEqual(restored[earlier.wakeDay]?.wakeStage, stage)
    }

    func testLegacyDiaryLoadsWithoutStageKey() throws {
        let checkIn = rating()
        var diary = Diary()
        XCTAssertTrue(diary.record(checkIn))
        let data = try JSONEncoder().encode(diary)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("wakeStage"))
        let restored = try JSONDecoder().decode(Diary.self, from: data)
        XCTAssertEqual(restored[checkIn.wakeDay]?.rating, checkIn)
        XCTAssertNil(restored[checkIn.wakeDay]?.wakeStage)
    }

    func testComparisonUsesSeparateDenominatorsAndNeverIncludesCandidates() throws {
        var diary = Diary()
        for (offset, value) in [Restedness.notAtAll, .veryWell, .slightly, .well].enumerated() {
            let hours = Double(offset * 24)
            let checkIn = rating(value, atHour: hours)
            XCTAssertTrue(diary.record(checkIn))
            guard offset < 3 else { continue }
            let stage = try XCTUnwrap(SleepWindow.wakeStage(in: [band(hours - 5, hours - 0.1, offset < 2 ? .core : .rem)], for: checkIn))
            XCTAssertTrue(diary.attach(stage, to: checkIn))
            let score = try XCTUnwrap(Score(offset == 0 ? 0 : 100, source: offset == 1 ? .notification : .manual))
            if offset == 1 { XCTAssertTrue(diary.stage(score, on: checkIn.wakeDay)) }
            else { XCTAssertTrue(diary.confirm(score, on: checkIn.wakeDay)) }
        }
        let comparison = WakeStageComparison(rows: diary.rows)
        XCTAssertEqual(comparison.matched, 3)
        XCTAssertEqual(comparison.missing, 1)
        let core = try XCTUnwrap(comparison.groups.first(where: { $0.stage == .core }))
        XCTAssertEqual(core.count, 2)
        XCTAssertEqual(core.medianRestedness, 3)
        XCTAssertEqual(core.scoreCount, 1)
        XCTAssertEqual(core.medianScore, 0)
        XCTAssertFalse(comparison.groups.contains { $0.stage == .deep })
    }
}
