import XCTest

/// 끌기 동작을 확인하고 스크린샷을 남긴다.
/// - Phase 11: 꾹 눌러 기간 만들기(28)
/// - Phase 15: "나중에" 항목을 꾹 눌러 덮개 달력에 넣기(29)
/// - 하루 상세에서 꾹 눌러 다른 날로 옮기기(33), 맨 위 X에 놓아 취소하기(40)
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
        XCTAssertEqual(app.switches["시간 지정"].value as? String, "0", "기간 일정은 시간 없이(종일) 시작해야 한다")
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
        // 놓을 칸(10/14, 가운데 줄 가운데 칸)의 화면 위치. 꾹 누르는 동안 "나중에" 목록 위에 거의 같은 자리의 달력이 덮인다.
        let targetFrame = app.buttons["calendar.day.2026-10-14"].frame

        tabButton("나중에", in: app).tap()
        let list = element("inbox.list", in: app)
        let row = list.cells.containing(.staticText, identifier: "책 반납하기").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        let target = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: targetFrame.midX, dy: targetFrame.midY))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.0, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)

        // 날짜 위에서 떼면 달력 탭으로 바뀌고 그 달이 보인다
        XCTAssertTrue(app.buttons["calendar.add"].waitForExistence(timeout: 5), "달력에 넣으면 달력 탭으로 바뀌어야 한다")
        XCTAssertTrue(app.staticTexts["2026년 10월"].exists)
        attachScreenshot(of: app, named: "29-inbox-drop")
        app.buttons["calendar.day.2026-10-14"].tap()
        let dayBar = app.navigationBars["10월 14일 (수)"]
        XCTAssertTrue(dayBar.waitForExistence(timeout: 5))
        XCTAssertTrue(
            element("dayDetail.list", in: app).staticTexts["책 반납하기"].waitForExistence(timeout: 5),
            "놓은 날의 하루 상세에 보여야 한다"
        )
        app.buttons["닫기"].tap()
        XCTAssertTrue(dayBar.waitForNonExistence(timeout: 5))

        tabButton("나중에", in: app).tap()
        XCTAssertTrue(list.staticTexts["선물 고르기"].waitForExistence(timeout: 5))
        XCTAssertFalse(list.staticTexts["책 반납하기"].exists, "달력에 넣은 항목은 나중에 목록에서 빠져야 한다")
    }

    @MainActor
    func testLongPressMovesAnItemFromTheDayDetailToAnotherDay() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))
        // 놓을 칸(10/27, 일정이 없는 날)의 화면 위치. 옮기는 동안 시트가 내려가며 사라져 달력이 보인다.
        let targetFrame = app.buttons["calendar.day.2026-10-27"].frame

        // 10/22 독서 모임(20:00–21:00)을 꾹 눌러 10/27에 놓는다
        app.buttons["calendar.day.2026-10-22"].tap()
        let dayBar = app.navigationBars["10월 22일 (목)"]
        XCTAssertTrue(dayBar.waitForExistence(timeout: 5))
        let row = element("dayDetail.list", in: app).staticTexts["독서 모임"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let target = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: targetFrame.midX, dy: targetFrame.midY))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.0, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)

        // 다른 날에 놓으면 시트가 닫히고 달력에 옮긴 결과가 보인다
        XCTAssertTrue(dayBar.waitForNonExistence(timeout: 5), "다른 날에 놓으면 하루 상세가 닫혀야 한다")
        attachScreenshot(of: app, named: "33-day-detail-moved")

        app.buttons["calendar.day.2026-10-27"].tap()
        let movedBar = app.navigationBars["10월 27일 (화)"]
        XCTAssertTrue(movedBar.waitForExistence(timeout: 5))
        let list = element("dayDetail.list", in: app)
        XCTAssertTrue(list.staticTexts["독서 모임"].waitForExistence(timeout: 5), "놓은 날의 하루 상세에 보여야 한다")
        XCTAssertTrue(labelContaining("8:00", in: list).exists, "시각은 그대로(20:00)여야 한다")
        app.buttons["닫기"].tap()
        XCTAssertTrue(movedBar.waitForNonExistence(timeout: 5))

        app.buttons["calendar.day.2026-10-22"].tap()
        XCTAssertTrue(dayBar.waitForExistence(timeout: 5))
        XCTAssertFalse(element("dayDetail.list", in: app).staticTexts["독서 모임"].exists, "원래 날에서는 빠져야 한다")
    }

    @MainActor
    func testDroppingOnTheCancelMarkKeepsTheItemAndBringsTheSheetBack() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))
        // 취소 표시(X)는 화면 맨 위 가운데, 달력 머리 줄(연·월)과 같은 높이에 뜬다.
        let header = app.buttons["calendar.monthTitle"].frame
        let cancelMark = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.midX, dy: header.midY))

        // 10/22 독서 모임을 꾹 눌러 달력 위를 지나 맨 위 X에서 놓는다
        app.buttons["calendar.day.2026-10-22"].tap()
        let dayBar = app.navigationBars["10월 22일 (목)"]
        XCTAssertTrue(dayBar.waitForExistence(timeout: 5))
        let row = element("dayDetail.list", in: app).staticTexts["독서 모임"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.0, thenDragTo: cancelMark, withVelocity: .slow, thenHoldForDuration: 0.5)

        // 옮기지 않고 시트가 원래 높이로 다시 보인다
        XCTAssertTrue(dayBar.waitForExistence(timeout: 5), "X에 놓으면 하루 상세가 다시 보여야 한다")
        let keptRow = element("dayDetail.list", in: app).staticTexts["독서 모임"]
        XCTAssertTrue(keptRow.waitForExistence(timeout: 5), "X에 놓으면 원래 날에 그대로 있어야 한다")
        // 시트가 다 나타난 뒤에 찍는다. 기다리지 못해도 아래의 누르기로 확인한다.
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: keptRow)
        _ = XCTWaiter.wait(for: [restored], timeout: 3)
        attachScreenshot(of: app, named: "40-day-detail-move-cancelled")

        // 감췄던 시트가 투명한 채로 남으면 누르기가 시트를 지나가 편집이 열리지 않는다
        keptRow.tap()
        let editorBar = app.navigationBars["일정 편집"]
        XCTAssertTrue(editorBar.waitForExistence(timeout: 5), "돌아온 시트의 행을 누르면 편집이 열려야 한다")
    }
}
