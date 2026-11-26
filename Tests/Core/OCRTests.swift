import Foundation
import XCTest
@testable import MorningCheckCore

final class OCRTests: XCTestCase {
    func testPublicAppleSupportCard() async throws {
        guard let path = ProcessInfo.processInfo.environment["MORNING_CHECK_APPLE_FIXTURE"] else {
            throw XCTSkip("Set MORNING_CHECK_APPLE_FIXTURE to Apple's published Sleep Score card to run OCR.")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let number = await ScoreOCR.read(data)
        // Published Apple Support illustration, 108906. Not a participant record.
        XCTAssertEqual(number, 93)
    }
}
