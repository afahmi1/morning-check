import Foundation
import XCTest
@testable import MorningCheckCore

final class AlertScoreInputTests: XCTestCase {
    private let zone = TimeZone(secondsFromGMT: 0)!
    private let noon = Date(timeIntervalSince1970: 43_200)

    func testMissingOrAmbiguousInputIsNotAttributedToTodaysHealthScore() {
        XCTAssertEqual(AlertScoreInput.evaluate(text: nil, receivedAt: noon, now: noon, zone: zone), .noText)
        XCTAssertEqual(AlertScoreInput.evaluate(text: "Sleep Score: 100", receivedAt: nil, now: noon, zone: zone), .noTimestamp)
        XCTAssertEqual(AlertScoreInput.evaluate(text: "Sleep Score: 0\nSleep Score: 100", receivedAt: noon, now: noon, zone: zone), .noUnambiguousScore)
        XCTAssertEqual(AlertScoreInput.evaluate(text: "Sleep Score: 100", receivedAt: noon.addingTimeInterval(-7201), now: noon, zone: zone), .stale)
        let midnight = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(AlertScoreInput.evaluate(text: "Sleep Score: 100", receivedAt: midnight.addingTimeInterval(-1), now: midnight, zone: zone), .stale)
    }

    func testAlertIsAnUnconfirmedCandidateAndCannotReplaceExistingData() throws {
        guard case .candidate(let score, let day) = AlertScoreInput.evaluate(text: "Sleep Score: 100", receivedAt: noon, now: noon, zone: zone)
        else { return XCTFail("Expected a candidate") }
        XCTAssertEqual(day, WakeDay.key(noon, in: zone))
        XCTAssertEqual(score.source, .notification)
        var diary = Diary()
        XCTAssertTrue(diary.stage(score, on: day))
        let conflicting = try XCTUnwrap(Score(0, source: .notification))
        XCTAssertFalse(diary.stage(conflicting, on: day))
        XCTAssertNil(diary[day]?.score)
        XCTAssertEqual(diary[day]?.candidate, score)
        XCTAssertTrue(diary.record(Rating(.well, at: noon, zone: zone, source: .phone)))
        XCTAssertTrue(diary.confirm(score, on: day))
        XCTAssertFalse(diary.stage(conflicting, on: day))
        XCTAssertEqual(diary[day]?.score, score)
    }
}
