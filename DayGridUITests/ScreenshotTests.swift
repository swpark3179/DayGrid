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
    func testDayDetailAndEditing() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))

        // 일정이 있는 날의 상세
        app.buttons["calendar.day.2026-10-19"].tap()
        XCTAssertTrue(app.navigationBars["10월 19일 (월)"].waitForExistence(timeout: 5))
        let list = app.descendants(matching: .any)["dayDetail.list"]
        XCTAssertTrue(list.staticTexts["주간 회의"].waitForExistence(timeout: 5))
        XCTAssertTrue(list.staticTexts["점심 약속"].exists)
        attachScreenshot(of: app, named: "08-day-detail")
        app.buttons["닫기"].tap()

        // 빈 날에 일정 추가
        app.buttons["calendar.day.2026-10-21"].tap()
        XCTAssertTrue(app.navigationBars["10월 21일 (수)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["일정 없음"].exists)
        app.buttons["dayDetail.add"].tap()
        let titleField = app.textFields["editor.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("UI Test")
        attachScreenshot(of: app, named: "09-item-editor")
        app.buttons["저장"].tap()

        let newRow = list.staticTexts["UI Test"]
        XCTAssertTrue(newRow.waitForExistence(timeout: 5), "저장한 일정이 하루 상세 목록에 보여야 한다")
        attachScreenshot(of: app, named: "10-day-detail-added")

        // 행을 누르면 편집 화면이 열린다
        newRow.tap()
        let editorBar = app.navigationBars["일정 편집"]
        XCTAssertTrue(editorBar.waitForExistence(timeout: 5), "행을 누르면 편집 화면이 열려야 한다")
        XCTAssertTrue(app.buttons["editor.delete"].exists, "편집 화면에는 삭제 버튼이 있어야 한다")
        app.buttons["취소"].tap()
        XCTAssertTrue(editorBar.waitForNonExistence(timeout: 5), "취소하면 편집 화면이 닫혀야 한다")

        // 밀어서 삭제
        XCTAssertTrue(newRow.waitForExistence(timeout: 5), "편집을 취소해도 일정은 그대로 있어야 한다")
        // 작은 제목 텍스트에서 swipeLeft()를 하면 끄는 거리가 짧아 탭으로 처리된다. 셀 전체 폭에서 끈다.
        let cell = list.cells.containing(.staticText, identifier: "UI Test").firstMatch
        XCTAssertTrue(cell.exists, "새 일정의 행 셀을 찾을 수 있어야 한다")
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: cell.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)))
        XCTAssertFalse(editorBar.exists, "밀기가 탭으로 처리돼 편집 화면이 열리면 안 된다")
        let deleteAction = list.buttons["삭제"]
        XCTAssertTrue(deleteAction.waitForExistence(timeout: 5), "밀면 목록 안에 삭제 버튼이 나타나야 한다")
        deleteAction.tap()
        XCTAssertTrue(newRow.waitForNonExistence(timeout: 5), "삭제한 일정은 목록에서 사라져야 한다")
        XCTAssertTrue(app.staticTexts["일정 없음"].waitForExistence(timeout: 5), "일정이 없으면 빈 화면 안내가 보여야 한다")
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
