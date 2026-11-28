import XCTest

final class MorningCheckUITests: XCTestCase {
    @MainActor
    func testAutomaticAlertScoreNeedsRatingButNoConfirmation() {
        let app = XCUIApplication()
        // Synthetic boundary value in a disposable in-memory diary; never live Health data.
        app.launchArguments = ["-isolated-ui-test", "-automatic-alert-score-test-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["phone-rating-3"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["confirmed-apple-score"].exists)
        XCTAssertFalse(app.textFields["apple-score-field"].exists)
        app.buttons["workspace-compare"].tap()
        XCTAssertFalse(app.staticTexts["confirmed-apple-score"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["pair-count"].firstMatch.label, "0 mornings with a score")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "morning-history-")).firstMatch.exists)
        app.buttons["workspace-checkIn"].tap()
        app.buttons["phone-rating-3"].tap()
        let score = app.staticTexts["confirmed-apple-score"]
        reveal(score, in: app)
        XCTAssertTrue(score.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Copied automatically from Health alert; not independently verified"].exists)
        XCTAssertFalse(app.buttons["Confirm 100"].exists)
        XCTAssertFalse(app.buttons["Save score"].exists)
        capture("Automatic alert score after rating (synthetic isolated fixture)")
        app.buttons["workspace-compare"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["pair-count"].firstMatch.label, "1 morning with a score")
    }

    @MainActor
    func testAutomaticAlertSettingStartsOffAndCanBeEnabled() {
        let app = XCUIApplication()
        app.launchArguments = ["-isolated-ui-test"]
        app.launch()
        app.buttons["Settings"].tap()
        let setting = app.switches["automatic-alert-scores-setting"]
        reveal(setting, in: app)
        XCTAssertTrue(setting.isHittable)
        XCTAssertEqual(setting.value as? String, "0")
        setting.tap()
        XCTAssertEqual(setting.value as? String, "1")
        let status = app.staticTexts["automatic-score-import-status"]
        reveal(status, in: app)
        XCTAssertTrue(status.exists)
    }

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
        XCTAssertEqual(paired.label, "1 morning with a score")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["1 of 1 high-score mornings felt only slightly rested or worse."].exists)

        let historyEntry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "morning-history-")).firstMatch
        reveal(historyEntry, in: app)
        XCTAssertTrue(historyEntry.isHittable)
        historyEntry.tap()
        XCTAssertTrue(app.staticTexts["confirmed-apple-score"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLastWatchStageAppearsAfterRatingAndComparesWithoutAScore() {
        let app = XCUIApplication()
        app.launchArguments = ["-isolated-ui-test", "-wake-stage-test-fixture"]
        app.launch()
        let action = app.buttons["phone-rating-3"]
        let stage = app.staticTexts["logged-wake-stage"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertFalse(stage.exists)
        action.tap()
        reveal(stage, in: app)
        XCTAssertTrue(stage.waitForExistence(timeout: 5))
        XCTAssertEqual(stage.label, "REM")
        XCTAssertFalse(app.staticTexts["confirmed-apple-score"].exists)
        capture("Stage after rating (isolated test fixture)")

        app.buttons["workspace-compare"].tap()
        let group = app.descendants(matching: .any)["wake-stage-group-rem"].firstMatch
        reveal(group, in: app)
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        XCTAssertTrue(group.label.contains("Median restedness: 3 / 5 (1)"), group.label)
        XCTAssertTrue(group.label.contains("No confirmed Sleep Scores"), group.label)
        capture("Stage comparison (isolated test fixture)")

        let history = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "morning-history-")).firstMatch
        reveal(history, in: app)
        XCTAssertTrue(history.isHittable)
        XCTAssertTrue(history.label.contains("Last stage: REM"), history.label)
        history.tap()
        reveal(stage, in: app)
        XCTAssertTrue(stage.isHittable)
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
        reveal(footer, in: app)
        guard footer.isHittable else { return XCTFail("Settings version footer is not visible") }
        XCTAssertTrue(footer.label.range(of: #"^DayBreak version [0-9]+(?:\.[0-9]+)+, build [0-9]+(?:\.[0-9]+)*$"#,
                                         options: .regularExpression) != nil, footer.label)
    }

    @MainActor
    func testPromptSettingsOfferEitherTrigger() {
        let app = XCUIApplication()
        app.launchArguments = ["-isolated-ui-test"]
        app.launch()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Prompt source"].waitForExistence(timeout: 5))
        let option = app.buttons["prompt-mode-either"]
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        XCTAssertEqual(option.label, "Watch sleep or iPhone alert")
        let stages = app.switches["log-wake-stage-setting"]
        reveal(stages, in: app)
        XCTAssertTrue(stages.isHittable)
        XCTAssertEqual(stages.value as? String, "0")
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

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !element.isHittable { app.swipeUp() }
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
