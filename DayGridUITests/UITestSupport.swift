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

    /// 라벨에 `text`가 들어 있는 첫 요소. 버튼 행은 안의 글자를 합친 라벨 하나로 보일 수 있어서 포함 여부로 찾는다.
    @MainActor
    func labelContaining(_ text: String, in parent: XCUIElement) -> XCUIElement {
        parent.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// 폼 아래쪽 행은 화면 밖이면 접근성 트리에 없으므로, 보일 때까지 위로 민다.
    @MainActor
    func scrollUntilVisible(_ target: XCUIElement, in app: XCUIApplication, attempts: Int = 3) {
        for _ in 0..<attempts where !(target.exists && target.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(target.waitForExistence(timeout: 5), "\(target) 를 찾을 수 있어야 한다")
    }
}
