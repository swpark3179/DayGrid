import XCTest

/// Phase 10 화면(연·월 이동, 본문 읽기 화면)을 샘플 데이터로 확인하고 스크린샷(26–27)을 남긴다.
final class CalendarExtrasTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMonthPicker() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))

        // 반복 탭 배지는 여기서 검사하지 않는다. iOS 26 탭 막대는 배지 숫자를 접근성 라벨·값에 넣지 않는다(라벨 "반복", 값 없음).
        // 개수는 단위 테스트(`RecurringTaskTests.sampleDataHasTwoDueTasksToday`)로, 표시는 기기 체크리스트 8-4로 확인한다.

        app.buttons["calendar.monthTitle"].tap()
        let pickerBar = app.navigationBars["날짜로 이동"]
        XCTAssertTrue(pickerBar.waitForExistence(timeout: 5), "연·월을 누르면 이동 시트가 열려야 한다")
        XCTAssertEqual(app.staticTexts["monthPicker.year"].label, "2026년")
        app.buttons["monthPicker.nextYear"].tap()
        XCTAssertEqual(app.staticTexts["monthPicker.year"].label, "2027년")
        attachScreenshot(of: app, named: "26-month-picker")

        app.buttons["monthPicker.month.3"].tap()
        XCTAssertTrue(pickerBar.waitForNonExistence(timeout: 5), "달을 고르면 시트가 닫혀야 한다")
        XCTAssertTrue(app.staticTexts["2027년 3월"].waitForExistence(timeout: 5), "고른 달로 바로 가야 한다")

        // 오늘 버튼으로 돌아온다
        app.buttons["오늘"].tap()
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testItemReader() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))
        app.buttons["calendar.day.2026-10-28"].tap()
        let dayBar = app.navigationBars["10월 28일 (수)"]
        XCTAssertTrue(dayBar.waitForExistence(timeout: 5))

        // 본문이 있는 "출장" 행의 오른쪽 버튼
        let trip = element("dayDetail.list", in: app).cells.containing(.staticText, identifier: "출장").firstMatch
        XCTAssertTrue(trip.waitForExistence(timeout: 5))
        let bodyButton = trip.buttons["dayDetail.body"]
        XCTAssertTrue(bodyButton.exists, "본문이 있으면 행 오른쪽에 본문 버튼이 있어야 한다")
        bodyButton.tap()

        let readerBar = app.navigationBars["본문"]
        XCTAssertTrue(readerBar.waitForExistence(timeout: 5), "본문 버튼을 누르면 읽기 화면이 열려야 한다")
        XCTAssertEqual(app.staticTexts["reader.title"].label, "출장")
        XCTAssertTrue(element("reader.category", in: app).label.contains("업무"), "카테고리가 보여야 한다")
        let page = app.webViews.firstMatch
        XCTAssertTrue(page.staticTexts["부산 출장"].waitForExistence(timeout: 15), "본문이 그려져야 한다")
        attachScreenshot(of: app, named: "27-item-reader")

        // 체크리스트 누르기: 웹뷰 체크박스가 접근성 트리에 보이는 경우에만 확인한다
        let boxes = page.checkBoxes
        if boxes.count > 1 {
            let second = boxes.element(boundBy: 1)
            let before = second.value as? String
            second.tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before ?? ""), object: boxes.element(boundBy: 1))
            XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 5), .completed, "체크리스트를 누르면 체크가 바뀌어야 한다")
        }

        // 뒤에 있는 하루 상세에도 "닫기"가 있으므로 읽기 화면의 막대 안에서 찾는다
        readerBar.buttons["닫기"].tap()
        XCTAssertTrue(readerBar.waitForNonExistence(timeout: 5))
        XCTAssertTrue(dayBar.exists, "읽기 화면을 닫으면 하루 상세로 돌아와야 한다")
    }
}
