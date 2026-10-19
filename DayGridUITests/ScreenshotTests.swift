import XCTest

/// 주요 화면을 고정된 날짜(2026-10-19)와 샘플 데이터로 띄우고 스크린샷을 남긴다.
/// CI가 결과 번들에서 스크린샷을 꺼내 `screenshots` 아티팩트로 올린다.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCalendarAndTabs() throws {
        let app = launchApp()

        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["주간 회의"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["스프린트"].exists)
        XCTAssertTrue(app.staticTexts["출장"].exists)
        attachScreenshot(of: app, named: "01-calendar")

        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["2026년 11월"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "02-calendar-november")

        app.buttons["오늘"].tap()
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 5))

        let tabs = [("나중에", "04-inbox"), ("반복", "05-recurring"), ("설정", "06-settings")]
        for (tabTitle, screenshotName) in tabs {
            tabButton(tabTitle, in: app).tap()
            XCTAssertTrue(app.navigationBars[tabTitle].waitForExistence(timeout: 5))
            attachScreenshot(of: app, named: screenshotName)
        }

        app.buttons["카테고리"].tap()
        XCTAssertTrue(app.navigationBars["카테고리"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["업무"].exists)
        attachScreenshot(of: app, named: "07-categories")
    }

    @MainActor
    func testCalendarDarkMode() throws {
        let app = launchApp(extraArguments: ["-UITestColorScheme", "dark"])
        XCTAssertTrue(app.staticTexts["주간 회의"].waitForExistence(timeout: 15))
        attachScreenshot(of: app, named: "03-calendar-dark")
    }

    @MainActor
    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestFixedToday", "2026-10-19",
            "-UITestSeedData",
            "-AppleLanguages", "(ko)",
            "-AppleLocale", "ko_KR",
        ] + extraArguments
        app.launch()
        return app
    }

    @MainActor
    private func tabButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let tabBarButton = app.tabBars.buttons[title]
        return tabBarButton.exists ? tabBarButton : app.buttons[title].firstMatch
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
