import XCTest

/// Phase 5–7 화면(본문, 휴일·생일, 반복 할일)을 샘플 데이터로 확인하고 스크린샷(16–24)을 남긴다.
final class FeatureScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Phase 5: 본문

    @MainActor
    func testBodyPreviewAndToolbar() throws {
        let app = launchApp()
        openTripBody(in: app)
        attachScreenshot(of: app, named: "16-body-preview")

        // 편집으로 바꾸면 키보드 위에 서식 툴바가 나온다
        let modePicker = app.segmentedControls["body.mode"]
        let editButton = modePicker.exists ? modePicker.buttons["편집"] : app.buttons["편집"].firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 5), "편집/미리보기 세그먼트가 있어야 한다")
        editButton.tap()
        let textView = app.textViews["body.editor"]
        XCTAssertTrue(textView.waitForExistence(timeout: 5), "편집으로 바꾸면 본문 편집기가 보여야 한다")
        textView.tap()
        let boldButton = app.buttons["굵게"]
        XCTAssertTrue(boldButton.waitForExistence(timeout: 5), "키보드 위에 서식 툴바가 있어야 한다")
        XCTAssertTrue(app.buttons["체크리스트"].exists)
        textView.typeText("Note ")
        boldButton.tap()
        XCTAssertTrue((textView.value as? String ?? "").contains("Note ****"), "굵게를 누르면 커서 자리에 ****가 들어가야 한다")
        attachScreenshot(of: app, named: "17-body-editor-toolbar")
    }

    @MainActor
    func testBodyPreviewDarkMode() throws {
        let app = launchApp(extraArguments: ["-UITestColorScheme", "dark"])
        openTripBody(in: app)
        attachScreenshot(of: app, named: "18-body-preview-dark")
    }

    /// 10월 28일 "출장"의 편집 화면에서 본문 화면을 연다. 본문이 있으므로 미리보기로 시작한다.
    @MainActor
    private func openTripBody(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))
        app.buttons["calendar.day.2026-10-28"].tap()
        XCTAssertTrue(app.navigationBars["10월 28일 (수)"].waitForExistence(timeout: 5))
        let dayList = element("dayDetail.list", in: app)
        let trip = dayList.staticTexts["출장"]
        XCTAssertTrue(trip.waitForExistence(timeout: 5), "출장이 하루 상세에 보여야 한다")
        trip.tap()
        XCTAssertTrue(app.navigationBars["일정 편집"].waitForExistence(timeout: 5))

        let bodyLink = app.buttons["editor.body"]
        scrollUntilVisible(bodyLink, in: app)
        bodyLink.tap()
        XCTAssertTrue(app.navigationBars["본문"].waitForExistence(timeout: 5), "본문 화면이 열려야 한다")
        let page = app.webViews.firstMatch
        XCTAssertTrue(page.staticTexts["부산 출장"].waitForExistence(timeout: 15), "미리보기에 제목이 그려져야 한다")
        XCTAssertTrue(page.staticTexts["고객사 미팅"].exists, "미리보기에 표가 그려져야 한다")
    }

    // MARK: - Phase 6: 휴일과 생일

    @MainActor
    func testHolidaysAndBirthdays() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))

        // 날짜 칸의 접근성 라벨에 휴일·생일·반복 할일 완료가 들어 있다
        let expectations = [
            ("2026-10-03", "개천절"),
            ("2026-10-05", "대체공휴일"),
            ("2026-10-09", "한글날"),
            ("2026-10-16", "회사 창립기념일"),
            ("2026-10-22", "김민수 생일"),
            ("2026-10-12", "반복 할일 1개 완료"),
        ]
        for (day, text) in expectations {
            let label = app.buttons["calendar.day.\(day)"].label
            XCTAssertTrue(label.contains(text), "\(day) 칸에 '\(text)'가 있어야 한다(지금: \(label))")
        }

        // 다가오는 생일 배너 → 생일 목록
        let banner = app.buttons["calendar.birthdays"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "30일 안의 생일이 있으면 배너가 보여야 한다")
        XCTAssertTrue(banner.label.contains("김민수"), "배너에 가장 가까운 생일이 보여야 한다(지금: \(banner.label))")
        banner.tap()
        let birthdaysBar = app.navigationBars["생일"]
        XCTAssertTrue(birthdaysBar.waitForExistence(timeout: 5), "배너를 누르면 생일 목록이 열려야 한다")
        let birthdayList = element("birthdays.list", in: app)
        XCTAssertTrue(labelContaining("김민수", in: birthdayList).waitForExistence(timeout: 5), "생일 목록에 김민수가 보여야 한다")
        XCTAssertTrue(labelContaining("D-3", in: birthdayList).exists, "가장 가까운 생일은 D-3이어야 한다")
        attachScreenshot(of: app, named: "19-birthdays")
        app.buttons["닫기"].tap()
        XCTAssertTrue(birthdaysBar.waitForNonExistence(timeout: 5))

        // 생일인 날의 하루 상세
        app.buttons["calendar.day.2026-10-22"].tap()
        let dayBar = app.navigationBars["10월 22일 (목)"]
        XCTAssertTrue(dayBar.waitForExistence(timeout: 5))
        XCTAssertTrue(element("dayDetail.list", in: app).staticTexts["김민수 생일"].waitForExistence(timeout: 5), "기념일 섹션에 생일이 보여야 한다")
        attachScreenshot(of: app, named: "20-day-detail-birthday")
        app.buttons["닫기"].tap()
        XCTAssertTrue(dayBar.waitForNonExistence(timeout: 5))

        // 설정 → 개인 휴일
        tabButton("설정", in: app).tap()
        XCTAssertTrue(app.navigationBars["설정"].waitForExistence(timeout: 5))
        app.buttons["개인 휴일"].tap()
        XCTAssertTrue(app.navigationBars["개인 휴일"].waitForExistence(timeout: 5))
        XCTAssertTrue(labelContaining("회사 창립기념일", in: element("holidays.list", in: app)).waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "21-personal-holidays")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["설정"].waitForExistence(timeout: 5))

        // 설정 → 생일 → 편집
        app.buttons["생일"].tap()
        XCTAssertTrue(app.navigationBars["생일"].waitForExistence(timeout: 5))
        let minsu = labelContaining("김민수", in: element("birthdays.list", in: app))
        XCTAssertTrue(minsu.waitForExistence(timeout: 5))
        minsu.tap()
        let editBar = app.navigationBars["생일 편집"]
        XCTAssertTrue(editBar.waitForExistence(timeout: 5), "생일을 누르면 편집 화면이 열려야 한다")
        XCTAssertEqual(app.textFields["person.name"].value as? String, "김민수")
        attachScreenshot(of: app, named: "22-person-edit")
        app.buttons["취소"].tap()
        XCTAssertTrue(editBar.waitForNonExistence(timeout: 5))
    }

    // MARK: - Phase 7: 반복 할일

    @MainActor
    func testRecurringTasks() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))

        // 하루 상세 아래쪽 "반복 할일" 섹션에서 오늘 주기를 체크하고 취소한다
        app.buttons["calendar.day.2026-10-19"].tap()
        let dayBar = app.navigationBars["10월 19일 (월)"]
        XCTAssertTrue(dayBar.waitForExistence(timeout: 5))
        let dayList = element("dayDetail.list", in: app)
        let dayRow = dayList.cells.containing(.staticText, identifier: "물 2L 마시기").firstMatch
        for _ in 0..<4 where !dayRow.exists {
            dayList.swipeUp()
        }
        XCTAssertTrue(dayRow.waitForExistence(timeout: 5), "하루 상세에 반복 할일 섹션이 있어야 한다")
        dayRow.buttons["완료로 표시"].tap()
        XCTAssertTrue(dayRow.buttons["완료 취소"].waitForExistence(timeout: 5), "하루 상세에서 체크할 수 있어야 한다")
        dayRow.buttons["완료 취소"].tap()
        XCTAssertTrue(dayRow.buttons["완료로 표시"].waitForExistence(timeout: 5), "하루 상세에서 체크를 취소할 수 있어야 한다")
        app.buttons["닫기"].tap()
        XCTAssertTrue(dayBar.waitForNonExistence(timeout: 5))

        tabButton("반복", in: app).tap()
        XCTAssertTrue(app.navigationBars["반복"].waitForExistence(timeout: 5))
        let list = element("recurring.list", in: app)
        for title in ["물 2L 마시기", "헬스장", "관리비 납부"] {
            XCTAssertTrue(list.staticTexts[title].waitForExistence(timeout: 5), "샘플 반복 할일 '\(title)'이 보여야 한다")
        }
        let summaries = list.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "이번 달"))
        XCTAssertGreaterThan(summaries.count, 0, "이번 달 완료 요약이 보여야 한다")
        attachScreenshot(of: app, named: "23-recurring")

        // 지금 주기 체크와 취소
        let water = list.cells.containing(.staticText, identifier: "물 2L 마시기").firstMatch
        let check = water.buttons["완료로 표시"]
        XCTAssertTrue(check.waitForExistence(timeout: 5), "아직 체크하지 않은 주기에는 체크박스가 있어야 한다")
        check.tap()
        XCTAssertTrue(water.buttons["완료 취소"].waitForExistence(timeout: 5), "체크하면 완료로 바뀌어야 한다")
        water.buttons["완료 취소"].tap()
        XCTAssertTrue(water.buttons["완료로 표시"].waitForExistence(timeout: 5), "다시 누르면 체크가 취소돼야 한다")

        // 편집 화면
        list.staticTexts["헬스장"].tap()
        let editBar = app.navigationBars["반복 할일 편집"]
        XCTAssertTrue(editBar.waitForExistence(timeout: 5), "행을 누르면 편집 화면이 열려야 한다")
        XCTAssertTrue(app.buttons["월"].exists, "매주 반복은 요일 버튼이 보여야 한다")
        attachScreenshot(of: app, named: "24-recurring-editor")
        app.buttons["취소"].tap()
        XCTAssertTrue(editBar.waitForNonExistence(timeout: 5))

        // 새 반복 할일
        app.buttons["recurring.add"].tap()
        let newBar = app.navigationBars["새 반복 할일"]
        XCTAssertTrue(newBar.waitForExistence(timeout: 5))
        let titleField = app.textFields["recurring.title"]
        titleField.tap()
        titleField.typeText("Stretch")
        app.buttons["저장"].tap()
        XCTAssertTrue(newBar.waitForNonExistence(timeout: 5))
        XCTAssertTrue(list.staticTexts["Stretch"].waitForExistence(timeout: 5), "저장한 반복 할일이 목록에 보여야 한다")
    }

    // MARK: - 도우미

    /// 라벨에 `text`가 들어 있는 첫 요소. 버튼 행은 안의 글자를 합친 라벨 하나로 보일 수 있어서 포함 여부로 찾는다.
    @MainActor
    private func labelContaining(_ text: String, in parent: XCUIElement) -> XCUIElement {
        parent.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// 폼 아래쪽 행은 화면 밖이면 접근성 트리에 없으므로, 보일 때까지 위로 민다.
    @MainActor
    private func scrollUntilVisible(_ target: XCUIElement, in app: XCUIApplication, attempts: Int = 3) {
        for _ in 0..<attempts where !(target.exists && target.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(target.waitForExistence(timeout: 5), "\(target) 를 찾을 수 있어야 한다")
    }
}
