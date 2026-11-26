import XCTest

final class MorningCheckUITests: XCTestCase {
    @MainActor
    func testRatingFirstThenPairWithScore() {
        let app = XCUIApplication()
        app.launchArguments = ["-isolated-ui-test"]
        app.launch()
        XCTAssertTrue(app.staticTexts["How rested do you feel?"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["DayBreak"].exists)
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
        XCTAssertTrue(app.staticTexts["confirmed-apple-score"].exists)
        app.buttons["workspace-compare"].tap()
        let paired = app.descendants(matching: .any)["pair-count"].firstMatch
        XCTAssertTrue(paired.waitForExistence(timeout: 5))
        XCTAssertEqual(paired.label, "1 paired morning")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["1 of 1 high-score mornings felt only slightly rested or worse."].exists)

        let historyEntry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "morning-history-")).firstMatch
        if !historyEntry.isHittable { app.swipeUp() }
        XCTAssertTrue(historyEntry.isHittable)
        historyEntry.tap()
        XCTAssertTrue(app.staticTexts["confirmed-apple-score"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWorkspaceNavigationAndSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-isolated-ui-test"]
        app.launch()
        XCTAssertTrue(app.buttons["workspace-compare"].waitForExistence(timeout: 10))
        app.buttons["workspace-compare"].tap()
        XCTAssertTrue(app.staticTexts["Compare your mornings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["phone-rating-1"].exists)
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Prompt source"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["workspace-checkIn"].tap()
        XCTAssertTrue(app.staticTexts["How rested do you feel?"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["apple-score-field"].exists)
    }
}
