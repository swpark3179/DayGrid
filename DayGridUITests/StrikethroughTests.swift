import XCTest

/// 취소선(보류·취소, 사용자 요청 2026-11-17). 지우지 않고 줄을 그어 기록으로 남긴다.
/// - 편집 화면의 "취소선" 토글로 긋고, 하루 상세(41)와 달력(42)에 흐리게 남는지 본다.
/// - 밀기 버튼("취소선 긋기")은 끝까지 밀면 첫 번째 동작("나중에")이 실행되어 UI 테스트로 누르기 어렵다. 기기 체크리스트 21장으로 확인한다.
/// - 할일을 남은 할일(배지)에서 빼는 것은 단위 테스트(`AppBadgeTests`)가 확인한다.
final class StrikethroughTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testStrikethroughKeepsTheRecord() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))
        app.buttons["calendar.day.2026-10-19"].tap()
        let dayBar = app.navigationBars["10월 19일 (월)"]
        XCTAssertTrue(dayBar.waitForExistence(timeout: 5))
        let list = element("dayDetail.list", in: app)
        let row = list.staticTexts["은행 업무"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertNotEqual(row.value as? String, "취소선", "처음에는 취소선이 없다")
        row.tap()

        let editorBar = app.navigationBars["일정 편집"]
        XCTAssertTrue(editorBar.waitForExistence(timeout: 5), "행을 누르면 편집 화면이 열려야 한다")
        let toggle = app.switches["editor.cancelled"]
        scrollUntilVisible(toggle, in: app)
        setSwitch(toggle, on: true)
        app.buttons["저장"].tap()
        XCTAssertTrue(editorBar.waitForNonExistence(timeout: 5), "저장하면 편집 화면이 닫혀야 한다")

        XCTAssertTrue(row.waitForExistence(timeout: 5), "취소선을 그어도 하루 상세에 남아야 한다")
        XCTAssertEqual(row.value as? String, "취소선", "제목에 취소선이 그어져야 한다")
        XCTAssertTrue(list.staticTexts["점심 약속"].exists)
        XCTAssertNotEqual(list.staticTexts["점심 약속"].value as? String, "취소선", "다른 일정은 그대로다")
        attachScreenshot(of: app, named: "41-strikethrough-day-detail")

        app.buttons["닫기"].tap()
        XCTAssertTrue(dayBar.waitForNonExistence(timeout: 5))
        let bar = app.staticTexts["은행 업무"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "취소선을 그은 일정도 달력에 남아야 한다")
        XCTAssertEqual(bar.value as? String, "취소선", "달력 막대에도 취소선이 그어져야 한다")
        attachScreenshot(of: app, named: "42-strikethrough-calendar")

        // 다시 열어 취소선을 지운다.
        app.buttons["calendar.day.2026-10-19"].tap()
        XCTAssertTrue(dayBar.waitForExistence(timeout: 5))
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(editorBar.waitForExistence(timeout: 5))
        scrollUntilVisible(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "1", "그은 일정을 열면 토글이 켜져 있어야 한다")
        setSwitch(toggle, on: false)
        app.buttons["저장"].tap()
        XCTAssertTrue(editorBar.waitForNonExistence(timeout: 5))
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertNotEqual(row.value as? String, "취소선", "토글을 끄고 저장하면 취소선이 지워져야 한다")
    }
}
