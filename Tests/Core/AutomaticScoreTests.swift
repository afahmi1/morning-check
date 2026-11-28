import Foundation
import XCTest
@testable import MorningCheckCore

/// Synthetic boundary fixtures only; none are personal health readings or diary records.
final class AutomaticScoreTests: XCTestCase {
    private let zone = TimeZone(secondsFromGMT: 0)!
    private let now = Date(timeIntervalSince1970: 43_200)

    private func evaluate(_ text: String? = "Sleep Score: 100", title: String? = "Very High Sleep Score", app: String? = "Health", received: Date? = Date(timeIntervalSince1970: 43_200)) -> AutomaticScoreInput {
        .evaluate(text: text, title: title, sourceApp: app, receivedAt: received, now: now, zone: zone)
    }

    func testAppleNotificationProseAndUnsafeNumericBoundaries() {
        // Synthetic domain boundaries substituted into vendor-style prose, not user observations.
        XCTAssertEqual(ScoreText.alertBody("You scored 100! Well done."), 100)
        XCTAssertEqual(ScoreText.alertBody("Your Sleep Score last night was 100 due to not getting enough sleep."), 100)
        for text in ["You scored 100–101.", "You scored 100/101.", "You scored 100.5.", "You scored -100.", "You scored 100⁄100.", "You scored 100; another score was 0.", "Sleep Score: 100\nYou scored 0.", "Sleep Score: 100\n[other metric] 0", "You slept with 8 hours.", "Your score was 100 hours."] {
            XCTAssertNil(ScoreText.alertBody(text), text)
        }
    }

    func testInstalledAppleNotificationTemplatesWhenProvided() throws {
        struct Fixture: Decodable { let key: String; let body: String; let value: Int; let title: String }
        guard let path = ProcessInfo.processInfo.environment["DAYBREAK_APPLE_ALERT_FIXTURE"] else {
            throw XCTSkip("Optional vendor-resource fixtures not supplied")
        }
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertFalse(fixtures.isEmpty)
        for fixture in fixtures {
            guard case .score(let score, _) = evaluate(fixture.body, title: fixture.title) else {
                XCTFail("Did not parse vendor template \(fixture.key)"); continue
            }
            XCTAssertEqual(score.value, fixture.value, fixture.key)
        }
    }

    func testAutomaticImportRequiresMatchingSourceTitleAndOriginalDate() throws {
        guard case .score(let score, let day) = evaluate() else { return XCTFail("Expected an automatic score") }
        XCTAssertEqual(score.source, .automaticNotification)
        XCTAssertEqual(score.value, 100)
        XCTAssertEqual(day, WakeDay.key(now, in: zone))
        XCTAssertEqual(evaluate(app: nil), .sourceMismatch)
        XCTAssertEqual(evaluate(app: "[unrelated app]"), .sourceMismatch)
        XCTAssertEqual(evaluate(title: "Sleep Score Now Available"), .sourceMismatch)
        XCTAssertEqual(evaluate(received: nil), .missingTimestamp)
        XCTAssertEqual(evaluate(received: now.addingTimeInterval(-7201)), .stale)
        XCTAssertEqual(evaluate(received: now.addingTimeInterval(1)), .stale)
        XCTAssertEqual(evaluate("Sleep Score: 0", title: "Very High Sleep Score"), .noScore)
        XCTAssertEqual(evaluate("Sleep Score: 100\nSleep Score: 0"), .noScore)
        XCTAssertEqual(evaluate("[missing score]"), .noScore)
        XCTAssertEqual(evaluate("100–101"), .noScore)
        XCTAssertEqual(evaluate("100/101"), .noScore)
        XCTAssertEqual(evaluate("100", app: "com.apple.Health"), evaluate())
    }

    func testAutomaticallyCapturedScoreStaysHiddenFromComparisonsUntilRating() throws {
        guard case .score(let score, let day) = evaluate() else { return XCTFail("Expected score") }
        var diary = Diary()
        XCTAssertTrue(diary.importAutomatically(score, on: day))
        XCTAssertNil(diary[day]?.rating)
        XCTAssertEqual(diary[day]?.score, score)
        XCTAssertEqual(Comparison(rows: diary.rows).pairs.count, 0)
        let restored = try JSONDecoder().decode(Diary.self, from: JSONEncoder().encode(diary))
        diary = restored
        let rating = Rating(.well, at: now, zone: zone, source: .watch)
        XCTAssertTrue(diary.record(rating))
        XCTAssertEqual(diary[day]?.score, score)
        XCTAssertNil(diary[day]?.candidate)
        XCTAssertEqual(Comparison(rows: diary.rows).pairs.count, 1)
    }

    func testImportAfterRatingDoesNotNeedConfirmationOrOverwriteScores() throws {
        let day = WakeDay.key(now, in: zone)
        let score = try XCTUnwrap(Score(100, source: .automaticNotification))
        var diary = Diary()
        XCTAssertTrue(diary.record(Rating(.well, at: now, zone: zone, source: .phone)))
        XCTAssertTrue(diary.importAutomatically(score, on: day))
        XCTAssertFalse(diary.importAutomatically(score, on: day))
        XCTAssertEqual(diary[day]?.score?.source, .automaticNotification)
        diary.clearScores(on: day)
        XCTAssertFalse(diary.importAutomatically(score, on: day))
        XCTAssertNil(diary[day]?.score)
        XCTAssertTrue(diary.confirm(try XCTUnwrap(Score(0, source: .manual)), on: day))
        XCTAssertFalse(diary.importAutomatically(score, on: day))
        XCTAssertEqual(diary[day]?.score?.source, .manual)
    }

    func testRemovedUnratedScoreCannotReappearOnDuplicateDelivery() throws {
        let day = WakeDay.key(now, in: zone)
        let score = try XCTUnwrap(Score(100, source: .automaticNotification))
        var diary = Diary()
        XCTAssertTrue(diary.importAutomatically(score, on: day))
        diary.clearScores(on: day)
        diary = try JSONDecoder().decode(Diary.self, from: JSONEncoder().encode(diary))
        XCTAssertFalse(diary.importAutomatically(score, on: day))
        XCTAssertFalse(diary.importAutomatically(try XCTUnwrap(Score(100, source: .manual)), on: day))
    }
}
