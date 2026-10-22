import XCTest

/// 일정 편집 화면의 배치와 "나중에 할일로 미루기"(사용자 요청 2026-10-22).
/// - 달력 일정에는 "날짜 지정" 토글이 없고, "시간 지정"이 종일 대신 쓰인다.
/// - 카테고리 → 본문 → 알림 순이고, 알림은 한 줄의 칩이다(38).
/// - "나중에 할일로 미루기"를 누르면 시트가 닫히고 "나중에" 탭이 열린다(39).
///
/// 알림 칩을 누르면 알림 권한 창이 떠서 화면을 가리므로, 칩은 누르지 않고 배치만 본다. 켜고 끄기는 기기 체크리스트 16장으로 확인한다.
final class EditorTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEditorLayoutAndMovingToTheInbox() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))
        app.buttons["calendar.day.2026-10-19"].tap()
        let dayBar = app.navigationBars["10월 19일 (월)"]
        XCTAssertTrue(dayBar.waitForExistence(timeout: 5))
        let dayList = element("dayDetail.list", in: app)
        let meeting = dayList.staticTexts["주간 회의"]
        XCTAssertTrue(meeting.waitForExistence(timeout: 5))
        meeting.tap()

        let editorBar = app.navigationBars["일정 편집"]
        XCTAssertTrue(editorBar.waitForExistence(timeout: 5), "행을 누르면 편집 화면이 열려야 한다")
        XCTAssertFalse(app.switches["날짜 지정"].exists, "달력 일정에는 날짜 지정 토글이 없어야 한다")
        XCTAssertFalse(app.switches["종일"].exists, "종일 토글은 시간 지정으로 바뀌어야 한다")
        XCTAssertEqual(app.switches["시간 지정"].value as? String, "1", "시간 일정은 시간 지정이 켜져 있어야 한다")

        // 알림은 본문 아래에 한 줄의 칩으로 있다.
        let chips = ["정시", "10분 전", "1시간 전", "하루 전"].map { app.buttons["reminder.\($0)"] }
        scrollUntilVisible(chips[0], in: app)
        for chip in chips {
            XCTAssertTrue(chip.exists, "\(chip) 칩이 있어야 한다")
            XCTAssertFalse(chip.isSelected, "샘플 일정에는 알림이 없다")
            XCTAssertEqual(chip.frame.midY, chips[0].frame.midY, accuracy: 1, "알림 칩은 한 줄이어야 한다")
        }
        let bodyLink = app.buttons["editor.body"]
        if bodyLink.exists {
            XCTAssertLessThan(bodyLink.frame.maxY, chips[0].frame.minY, "알림은 본문 아래에 있어야 한다")
        }
        let category = app.buttons["category.업무"]
        if category.exists {
            XCTAssertLessThan(category.frame.maxY, chips[0].frame.minY, "알림은 카테고리 아래에 있어야 한다")
        }
        attachScreenshot(of: app, named: "38-editor-reminders")

        // 삭제 바로 위의 "나중에 할일로 미루기"
        let moveToInbox = app.buttons["editor.moveToInbox"]
        scrollUntilVisible(moveToInbox, in: app)
        let delete = app.buttons["editor.delete"]
        if delete.exists {
            XCTAssertLessThan(moveToInbox.frame.minY, delete.frame.minY, "미루기는 삭제 위에 있어야 한다")
        }
        moveToInbox.tap()

        XCTAssertTrue(editorBar.waitForNonExistence(timeout: 5), "미루면 편집 화면이 닫혀야 한다")
        XCTAssertTrue(dayBar.waitForNonExistence(timeout: 5), "미루면 하루 상세도 닫혀야 한다")
        XCTAssertTrue(app.navigationBars["나중에"].waitForExistence(timeout: 5), "미루면 나중에 탭이 열려야 한다")
        let inbox = element("inbox.list", in: app)
        XCTAssertTrue(inbox.staticTexts["주간 회의"].waitForExistence(timeout: 5), "미룬 일정이 나중에 목록에 있어야 한다")
        attachScreenshot(of: app, named: "39-editor-moved-to-inbox")

        // 달력의 그 날에서는 빠진다.
        tabButton("달력", in: app).tap()
        app.buttons["calendar.day.2026-10-19"].tap()
        XCTAssertTrue(dayBar.waitForExistence(timeout: 5))
        XCTAssertTrue(dayList.staticTexts["점심 약속"].waitForExistence(timeout: 5))
        XCTAssertFalse(dayList.staticTexts["주간 회의"].exists, "미룬 일정은 하루 상세에서 빠져야 한다")
    }
}
