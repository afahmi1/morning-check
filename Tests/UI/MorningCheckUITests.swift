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
    func testAppearanceSelectionAndPersistence() {
        let app = XCUIApplication()
        app.launchArguments = ["-isolated-ui-test"]
        app.launchEnvironment["DAYBREAK_TEST_APPEARANCE_SUITE"] = "daybreak-tests-\(UUID().uuidString)"
        app.launch()
        app.buttons["Settings"].tap()
        let row = app.buttons["appearance-settings"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, "Thermocline · Crown · System")
        row.tap()

        let classic = app.buttons["theme-paperAsh"]
        let thermocline = app.buttons["theme-thermocline"]
        let dark = app.buttons["mode-dark"]
        let light = app.buttons["mode-light"]
        let system = app.buttons["mode-system"]
        let plum = app.buttons["accent-plum"]
        XCTAssertTrue(thermocline.waitForExistence(timeout: 5))
        XCTAssertTrue(thermocline.isSelected)
        XCTAssertTrue(system.isSelected)
        XCTAssertTrue(app.buttons["accent-crown"].isSelected)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "accent-")).count, 7)

        plum.tap()
        XCTAssertTrue(plum.isSelected)
        classic.tap()
        XCTAssertTrue(classic.isSelected)
        XCTAssertFalse(plum.exists)
        light.tap()
        XCTAssertTrue(light.isSelected)
        XCTAssertTrue(app.staticTexts["Fixed to Paper’s original burnt orange."].exists)
        dark.tap()
        XCTAssertTrue(dark.isSelected)
        XCTAssertTrue(app.staticTexts["Fixed to Ash’s original violet."].exists)
        thermocline.tap()
        XCTAssertTrue(plum.isSelected)
        app.navigationBars["Appearance"].buttons.firstMatch.tap()
        XCTAssertEqual(row.value as? String, "Thermocline · Plum · Dark")

        app.terminate()
        app.launch()
        app.buttons["Settings"].tap()
        XCTAssertEqual(row.value as? String, "Thermocline · Plum · Dark")
        row.tap()
        XCTAssertTrue(plum.isSelected)
        XCTAssertTrue(dark.isSelected)
        system.tap()
        XCTAssertTrue(system.isSelected)
    }

    @MainActor
    func testSettingsFooterIdentifiesInstalledVersionAndBuild() {
        let app = XCUIApplication()
        app.launchArguments = ["-isolated-ui-test"]
        app.launch()
        app.buttons["Settings"].tap()

        let footer = app.staticTexts["daybreak-version"]
        if !footer.isHittable { app.swipeUp() }
        guard footer.isHittable else { return XCTFail("Settings version footer is not visible") }
        XCTAssertTrue(footer.label.range(of: #"^DayBreak version [0-9]+(?:\.[0-9]+)+, build [0-9]+(?:\.[0-9]+)*$"#,
                                         options: .regularExpression) != nil, footer.label)
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
