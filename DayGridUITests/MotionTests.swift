import XCTest

/// Phase 17(UI·모션 개선)에서 화면에 새로 생긴 것을 확인하고 스크린샷을 남긴다.
/// - 꾹 누르기 안내 팁(35): 테스트에서는 팁을 숨기므로 `-UITestShowTips`로 켠다.
/// - 되돌리기 토스트(36)
/// - 편집 화면의 카테고리 칩(37)
///
/// 움직임(링, 띠, 펄스, 튀기)은 스크린샷으로 남지 않으므로 기기 체크리스트 15장으로 확인한다.
final class MotionTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGestureTipsAreShownOnce() throws {
        let app = launchApp(extraArguments: ["-UITestShowTips"])
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["꾹 눌러 기간 일정 만들기"].waitForExistence(timeout: 5), "달력에 기간 만들기 팁이 보여야 한다")
        attachScreenshot(of: app, named: "35-gesture-tip")

        tabButton("나중에", in: app).tap()
        XCTAssertTrue(app.navigationBars["나중에"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["꾹 눌러 달력에 넣기"].waitForExistence(timeout: 5), "나중에 목록에 달력에 넣기 팁이 보여야 한다")
    }

    @MainActor
    func testUndoToastBringsBackASwipeDeletedItem() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))
        app.buttons["calendar.day.2026-10-19"].tap()
        let dayBar = app.navigationBars["10월 19일 (월)"]
        XCTAssertTrue(dayBar.waitForExistence(timeout: 5))
        let list = element("dayDetail.list", in: app)
        let row = list.staticTexts["은행 업무"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        // 왼쪽으로 밀어 지운다. 끝까지 밀면 버튼을 누르지 않아도 바로 지워진다(전체 밀기).
        drag(list.cells.containing(.staticText, identifier: "은행 업무").firstMatch, from: 0.85, to: 0.15)
        let deleteAction = list.buttons["삭제"]
        if deleteAction.waitForExistence(timeout: 2) {
            deleteAction.tap()
        }
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "지운 일정은 목록에서 사라져야 한다")

        let undo = app.buttons["toast.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "지우면 실행 취소 토스트가 떠야 한다")
        attachScreenshot(of: app, named: "36-undo-toast")
        undo.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "실행 취소하면 지운 일정이 돌아와야 한다")
        XCTAssertTrue(undo.waitForNonExistence(timeout: 5), "실행 취소하면 토스트가 내려가야 한다")

        app.buttons["닫기"].tap()
        XCTAssertTrue(dayBar.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["은행 업무"].waitForExistence(timeout: 5), "되살린 일정이 달력에도 보여야 한다")
    }

    @MainActor
    func testCategoryChipsSelectACategory() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))
        app.buttons["calendar.add"].tap()
        let editorBar = app.navigationBars["새 일정"]
        XCTAssertTrue(editorBar.waitForExistence(timeout: 5))

        let personal = app.buttons["category.개인"]
        let work = app.buttons["category.업무"]
        scrollUntilVisible(work, in: app)
        XCTAssertTrue(personal.isSelected, "새 일정은 첫 카테고리(개인)로 시작해야 한다")
        work.tap()
        XCTAssertTrue(work.isSelected, "누른 칩이 골라져야 한다")
        XCTAssertFalse(personal.isSelected, "고른 칩은 하나뿐이어야 한다")
        attachScreenshot(of: app, named: "37-category-chips")

        app.buttons["취소"].tap()
        XCTAssertTrue(editorBar.waitForNonExistence(timeout: 5))
    }
}
