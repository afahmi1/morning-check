import XCTest

final class MorningCheckUITests: XCTestCase {
    @MainActor
    func testRatingFirstThenPairWithScore() {
        let app = XCUIApplication()
        app.launchArguments = ["-isolated-ui-test"]
        app.launch()
        XCTAssertTrue(app.staticTexts["How rested do you feel?"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["apple-score-field"].exists)
        app.buttons["phone-rating-1"].tap()
        let field = app.textFields["apple-score-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save score"].isEnabled)
        field.tap()
        // Boundary of the product's input domain, in a disposable in-memory UI test.
        field.typeText("100")
        XCTAssertTrue(app.buttons["Save score"].isEnabled)
        app.buttons["Save score"].tap()
        XCTAssertTrue(app.staticTexts["100 / 100"].exists)
        app.tabBars.buttons["Compare"].tap()
        XCTAssertTrue(app.staticTexts["pair-count"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["pair-count"].label.contains("1 paired mornings"))
        XCTAssertTrue(app.staticTexts["1 of 1 high-score mornings felt only slightly rested or worse."].exists)
    }
}
