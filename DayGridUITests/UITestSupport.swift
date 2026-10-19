import XCTest

/// UI 테스트가 같이 쓰는 도우미. 날짜(2026-10-19)와 샘플 데이터를 고정해 앱을 띄우고, 스크린샷을 남긴다.
extension XCTestCase {
    @MainActor
    func launchApp(extraArguments: [String] = []) -> XCUIApplication {
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

    /// 목록 행을 셀 좌표로 끈다. 작은 텍스트에서 swipe를 하면 끄는 거리가 짧아 탭으로 처리된다.
    @MainActor
    func drag(_ cell: XCUIElement, from startX: CGFloat, to endX: CGFloat) {
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "끌 행 셀을 찾을 수 있어야 한다")
        cell.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: cell.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: 0.5)))
    }

    @MainActor
    func tabButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let tabBarButton = app.tabBars.buttons[title]
        return tabBarButton.exists ? tabBarButton : app.buttons[title].firstMatch
    }

    /// `NN-화면` 이름으로 스크린샷을 남긴다. CI가 `screenshots` 아티팩트로 올린다.
    @MainActor
    func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 시트 안의 목록. 화면 뒤 달력에도 같은 글자가 보이므로 시트 안의 텍스트는 이 아래에서 찾는다.
    @MainActor
    func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
