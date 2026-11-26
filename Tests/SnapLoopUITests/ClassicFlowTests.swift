import XCTest

final class ClassicFlowTests: XCTestCase {
    @MainActor
    func testTrainingClassicOverloadRestartAndRecords() throws {
        let app = launchGame()
        saveScreenshot("Home", app: app)
        app.buttons["start-game"].tap()
        let arena = app.coordinate(withNormalizedOffset: CGVector(dx: 0.49, dy: 0.67))
        let next = app.buttons["advance-lesson"]
        for (index, duration) in [0.70, 0.80, 0.80, 2.10].enumerated() {
            XCTAssertTrue(app.staticTexts["battle-hint"].waitForExistence(timeout: 3))
            if index == 0 { saveScreenshot("Training", app: app) }
            arena.press(forDuration: duration)
            XCTAssertTrue(next.waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts["Drill complete"].exists)
            next.tap()
        }
        let hint = app.staticTexts["battle-hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 3))
        XCTAssertEqual(hint.label, "Hold to start")
        arena.press(forDuration: 2.10)
        let restart = app.buttons["restart-game"]
        XCTAssertTrue(restart.waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Ring overload"].exists)
        saveScreenshot("Results", app: app)
        restart.tap()
        XCTAssertTrue(hint.waitForExistence(timeout: 3))
        XCTAssertEqual(hint.label, "Hold to start")
        XCTAssertFalse(restart.exists)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Records"].waitForExistence(timeout: 6))
        app.buttons["Records"].tap()
        XCTAssertTrue(app.staticTexts["Ring overload"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testPauseResumeAndSystemInterruption() throws {
        let app = launchGame()
        app.buttons["start-game"].tap()
        let skip = app.buttons["skip-practice"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        skip.tap()
        let hint = app.staticTexts["battle-hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 3))
        XCTAssertEqual(hint.label, "Hold to start")
        let arena = app.coordinate(withNormalizedOffset: CGVector(dx: 0.49, dy: 0.67))
        arena.press(forDuration: 0.16)
        let pause = app.buttons["pause-game"]
        XCTAssertTrue(pause.waitForExistence(timeout: 3))
        pause.tap()
        let resume = app.buttons["resume-game"]
        XCTAssertTrue(resume.waitForExistence(timeout: 3))
        saveScreenshot("Pause", app: app)
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.switches["Haptics"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        XCTAssertTrue(resume.waitForExistence(timeout: 3))
        resume.tap()
        XCTAssertTrue(hint.waitForExistence(timeout: 3))
        XCTAssertEqual(hint.label, "Hold to resume")
        arena.press(forDuration: 0.35)
        XCTAssertTrue(pause.waitForExistence(timeout: 3))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(resume.waitForExistence(timeout: 3))
    }

    @MainActor
    private func launchGame() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SNAP_LOOP_STORAGE_SUITE"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["start-game"].waitForExistence(timeout: 6))
        return app
    }

    @MainActor
    private func saveScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
