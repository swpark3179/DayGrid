import XCTest

/// Phase 11 끌기 동작(꾹 눌러 기간 만들기, "나중에" → 달력 놓기)을 확인하고 스크린샷(28–29)을 남긴다.
final class DragTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLongPressAndDragCreatesARange() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))

        // 10/21을 꾹 누른 채 10/23까지 끈다
        let start = app.buttons["calendar.day.2026-10-21"]
        let end = app.buttons["calendar.day.2026-10-23"]
        start.press(forDuration: 1.0, thenDragTo: end)

        let editorBar = app.navigationBars["새 일정"]
        XCTAssertTrue(editorBar.waitForExistence(timeout: 5), "끌고 놓으면 새 일정 화면이 열려야 한다")
        XCTAssertEqual(app.switches["종일"].value as? String, "1", "기간 일정은 종일로 시작해야 한다")
        let title = app.textFields["editor.title"]
        title.tap()
        title.typeText("Range")
        attachScreenshot(of: app, named: "28-range-editor")
        app.buttons["저장"].tap()
        XCTAssertTrue(editorBar.waitForNonExistence(timeout: 5))

        // 가운데 날(10/22)의 하루 상세에 있다
        app.buttons["calendar.day.2026-10-22"].tap()
        let dayBar = app.navigationBars["10월 22일 (목)"]
        XCTAssertTrue(dayBar.waitForExistence(timeout: 5))
        XCTAssertTrue(element("dayDetail.list", in: app).staticTexts["Range"].waitForExistence(timeout: 5), "기간 안의 날에 보여야 한다")
        app.buttons["닫기"].tap()
        XCTAssertTrue(dayBar.waitForNonExistence(timeout: 5))

        // 짧게 누르면 하루 상세가 그대로 열린다
        app.buttons["calendar.day.2026-10-21"].tap()
        XCTAssertTrue(app.navigationBars["10월 21일 (수)"].waitForExistence(timeout: 5), "짧게 누르면 하루 상세가 열려야 한다")
    }

    @MainActor
    func testDraggingAnInboxItemOntoTheCalendar() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))
        // 놓을 칸의 화면 위치를 먼저 기록한다(끌기 중에는 달력 탭으로 바뀐 뒤에야 보인다)
        let targetFrame = app.buttons["calendar.day.2026-10-22"].frame

        tabButton("나중에", in: app).tap()
        let list = element("inbox.list", in: app)
        let row = list.cells.containing(.staticText, identifier: "책 반납하기").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        let origin = app.coordinate(withNormalizedOffset: .zero)
        let target = origin.withOffset(CGVector(dx: targetFrame.midX, dy: targetFrame.midY))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.2, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.6)

        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 5), "끌기를 시작하면 달력으로 바뀌어야 한다")
        attachScreenshot(of: app, named: "29-inbox-drop")
        app.buttons["calendar.day.2026-10-22"].tap()
        let dayBar = app.navigationBars["10월 22일 (목)"]
        XCTAssertTrue(dayBar.waitForExistence(timeout: 5))
        XCTAssertTrue(
            element("dayDetail.list", in: app).staticTexts["책 반납하기"].waitForExistence(timeout: 5),
            "놓은 날의 하루 상세에 보여야 한다"
        )
    }
}
