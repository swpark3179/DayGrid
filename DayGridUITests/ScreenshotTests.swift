import XCTest

/// 주요 화면을 고정된 날짜·데이터로 띄우고 스크린샷을 남긴다.
/// CI가 결과 번들에서 스크린샷을 꺼내 아티팩트로 올린다.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMainTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestFixedToday", "2026-10-19",
            "-UITestSeedData",
            "-AppleLanguages", "(ko)",
            "-AppleLocale", "ko_KR",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["달력 준비 중"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["오늘은 2026년 10월 19일 (월)입니다."].exists)
        attachScreenshot(of: app, named: "01-calendar")

        let tabs = [("나중에", "02-inbox"), ("반복", "03-recurring"), ("설정", "04-settings")]
        for (tabTitle, screenshotName) in tabs {
            tabButton(tabTitle, in: app).tap()
            XCTAssertTrue(app.navigationBars[tabTitle].waitForExistence(timeout: 5))
            attachScreenshot(of: app, named: screenshotName)
        }
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
