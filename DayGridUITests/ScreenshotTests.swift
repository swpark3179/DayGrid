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

    /// 설정의 테마를 실행 인자 `-appearance dark`(UserDefaults 인자 도메인)로 다크로 둔다.
    /// Picker를 눌러 바꾸면 값이 시뮬레이터에 남아 다른 테스트의 스크린샷이 바뀐다.
    @MainActor
    func testCalendarDarkMode() throws {
        let app = launchApp(extraArguments: ["-appearance", "dark"])
        XCTAssertTrue(app.staticTexts["주간 회의"].waitForExistence(timeout: 15))
        attachScreenshot(of: app, named: "03-calendar-dark")

        tabButton("설정", in: app).tap()
        XCTAssertTrue(app.navigationBars["설정"].waitForExistence(timeout: 5))
        let theme = element("settings.appearance", in: app).firstMatch
        XCTAssertTrue(theme.waitForExistence(timeout: 5), "설정에 테마가 있어야 한다")
        let shown = [theme.label, theme.value as? String ?? ""].joined(separator: " ")
        XCTAssertTrue(shown.contains("다크") || app.staticTexts["다크"].exists, "테마가 다크로 보여야 한다(지금: \(shown))")
        attachScreenshot(of: app, named: "34-settings-dark")
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
        // 삭제 버튼은 폼 아래쪽이라 화면 밖에 있을 수 있다. 제목으로 같은 일정을 열었는지 본다.
        XCTAssertEqual(app.textFields["editor.title"].value as? String, "UI Test", "누른 일정의 편집 화면이 열려야 한다")
        app.buttons["취소"].tap()
        XCTAssertTrue(editorBar.waitForNonExistence(timeout: 5), "취소하면 편집 화면이 닫혀야 한다")

        // 밀어서 삭제
        XCTAssertTrue(newRow.waitForExistence(timeout: 5), "편집을 취소해도 일정은 그대로 있어야 한다")
        drag(list.cells.containing(.staticText, identifier: "UI Test").firstMatch, from: 0.85, to: 0.15)
        XCTAssertFalse(editorBar.exists, "밀기가 탭으로 처리돼 편집 화면이 열리면 안 된다")
        let deleteAction = list.buttons["삭제"]
        XCTAssertTrue(deleteAction.waitForExistence(timeout: 5), "밀면 목록 안에 삭제 버튼이 나타나야 한다")
        deleteAction.tap()
        XCTAssertTrue(newRow.waitForNonExistence(timeout: 5), "삭제한 일정은 목록에서 사라져야 한다")
        XCTAssertTrue(app.staticTexts["일정 없음"].waitForExistence(timeout: 5), "일정이 없으면 빈 화면 안내가 보여야 한다")
    }

    @MainActor
    func testInboxAssignAndDefer() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))
        tabButton("나중에", in: app).tap()
        XCTAssertTrue(app.navigationBars["나중에"].waitForExistence(timeout: 5))
        let list = app.descendants(matching: .any)["inbox.list"]
        XCTAssertTrue(list.staticTexts["책 반납하기"].waitForExistence(timeout: 5), "샘플 할일이 나중에 목록에 보여야 한다")

        // 빠른 입력: 엔터를 치면 바로 들어가고, 입력창에 이어서 쓸 수 있다
        let input = app.textFields["inbox.input"]
        input.tap()
        input.typeText("Inbox Task\n")
        XCTAssertTrue(list.staticTexts["Inbox Task"].waitForExistence(timeout: 5), "엔터를 치면 바로 목록에 들어가야 한다")
        input.typeText("Second Task\n")
        XCTAssertTrue(list.staticTexts["Second Task"].waitForExistence(timeout: 5), "입력창에 이어서 쓸 수 있어야 한다")
        attachScreenshot(of: app, named: "11-inbox-quick-add")
        // 빈 채로 엔터를 치면 입력을 마친다
        input.typeText("\n")

        // 왼쪽으로 밀어서 날짜 정하기
        drag(list.cells.containing(.staticText, identifier: "Inbox Task").firstMatch, from: 0.85, to: 0.15)
        let assignAction = list.buttons["날짜"]
        XCTAssertTrue(assignAction.waitForExistence(timeout: 5), "밀면 목록 안에 날짜 버튼이 나타나야 한다")
        assignAction.tap()
        let assignBar = app.navigationBars["날짜 정하기"]
        XCTAssertTrue(assignBar.waitForExistence(timeout: 5), "날짜 정하기 시트가 열려야 한다")
        app.buttons["assign.tomorrow"].tap()
        attachScreenshot(of: app, named: "12-assign-date")
        app.buttons["assign.save"].tap()
        XCTAssertTrue(assignBar.waitForNonExistence(timeout: 5), "정하기를 누르면 시트가 닫혀야 한다")
        XCTAssertTrue(list.staticTexts["Inbox Task"].waitForNonExistence(timeout: 5), "날짜를 정하면 나중에 목록에서 빠져야 한다")

        // 달력과 하루 상세에 보인다
        tabButton("달력", in: app).tap()
        XCTAssertTrue(app.staticTexts["Inbox Task"].waitForExistence(timeout: 5), "날짜를 정한 할일이 달력에 보여야 한다")
        app.buttons["calendar.day.2026-10-20"].tap()
        let dayBar = app.navigationBars["10월 20일 (화)"]
        XCTAssertTrue(dayBar.waitForExistence(timeout: 5))
        let dayList = app.descendants(matching: .any)["dayDetail.list"]
        XCTAssertTrue(dayList.staticTexts["Inbox Task"].waitForExistence(timeout: 5), "내일(10/20) 상세에 보여야 한다")
        attachScreenshot(of: app, named: "13-day-detail-assigned")

        // 오른쪽으로 밀어서 나중에 하기. 끝까지 밀면 버튼을 누르지 않아도 바로 실행된다(전체 밀기).
        drag(dayList.cells.containing(.staticText, identifier: "Inbox Task").firstMatch, from: 0.15, to: 0.85)
        let deferAction = dayList.buttons["나중에"]
        if deferAction.waitForExistence(timeout: 2) {
            deferAction.tap()
        }
        XCTAssertTrue(dayList.staticTexts["Inbox Task"].waitForNonExistence(timeout: 5), "오른쪽으로 밀어 미루면 하루 상세에서 빠져야 한다")
        XCTAssertTrue(app.staticTexts["일정 없음"].waitForExistence(timeout: 5))
        app.buttons["닫기"].tap()
        XCTAssertTrue(dayBar.waitForNonExistence(timeout: 5), "닫기를 누르면 하루 상세가 닫혀야 한다")

        // 나중에 목록으로 돌아온다
        tabButton("나중에", in: app).tap()
        XCTAssertTrue(list.staticTexts["Inbox Task"].waitForExistence(timeout: 5), "미룬 할일이 나중에 목록에 돌아와야 한다")
        attachScreenshot(of: app, named: "14-inbox-deferred")
    }

    @MainActor
    func testQuickAddShortcut() throws {
        let app = launchApp(extraArguments: ["-UITestQuickAction", "addTask"])
        XCTAssertTrue(app.navigationBars["나중에"].waitForExistence(timeout: 15), "퀵 액션으로 열면 나중에 탭이 보여야 한다")
        let input = app.textFields["inbox.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: input)
        XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 5), .completed, "입력창에 바로 쓸 수 있어야 한다")
        input.typeText("Shortcut Task\n")
        XCTAssertTrue(app.descendants(matching: .any)["inbox.list"].staticTexts["Shortcut Task"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "15-quick-add-shortcut")

        // 입력창 안을 누르면 계속 쓰고, 밖(제목 줄)을 누르면 키보드가 내려간다.
        // 시뮬레이터에 하드웨어 키보드가 붙어 있으면 화면 키보드가 보이지 않으므로 입력창 포커스로 확인한다.
        func waitForFocus(_ isFocused: Bool) -> XCTWaiter.Result {
            let predicate = NSPredicate(format: "hasKeyboardFocus == %@", NSNumber(value: isFocused))
            return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: input)], timeout: 5)
        }
        XCTAssertEqual(waitForFocus(true), .completed, "엔터 뒤에도 이어서 쓸 수 있어야 한다")
        input.tap()
        XCTAssertEqual(waitForFocus(true), .completed, "입력창 안을 누르면 키보드가 내려가지 않아야 한다")
        // 제목 줄의 왼쪽(편집 버튼이 없는 곳)
        app.navigationBars["나중에"].coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
        XCTAssertEqual(waitForFocus(false), .completed, "입력창 밖을 누르면 키보드가 내려가야 한다")
    }
}
