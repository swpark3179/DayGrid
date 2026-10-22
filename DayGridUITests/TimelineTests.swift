import XCTest

/// Phase 13 하루 상세 타임라인을 샘플 데이터로 확인하고 스크린샷(30–32)을 남긴다.
///
/// 보기 방식은 실행 인자 `-dayDetailStyle timeline`(UserDefaults 인자 도메인)으로 켠다.
/// 설정의 Picker를 눌러 바꾸면 값이 시뮬레이터에 남아, 다른 테스트의 하루 상세가 타임라인으로 바뀐다.
final class TimelineTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchTimelineApp() -> XCUIApplication {
        launchApp(extraArguments: ["-dayDetailStyle", "timeline"])
    }

    @MainActor
    func testTimelineSettings() throws {
        let app = launchTimelineApp()
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))
        tabButton("설정", in: app).tap()
        XCTAssertTrue(app.navigationBars["설정"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("settings.dayDetailStyle", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("settings.workdayStart", in: app).exists, "타임라인이면 업무 시작 시간이 보여야 한다")
        XCTAssertTrue(element("settings.workdayEnd", in: app).exists, "타임라인이면 업무 종료 시간이 보여야 한다")
        attachScreenshot(of: app, named: "30-settings-day-detail")
    }

    @MainActor
    func testDayTimeline() throws {
        let app = launchTimelineApp()
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))

        // 10/30: 세미나 9시, 병원 15시, 저녁 약속 19시(업무 시간 밖) → 9–20시. 종일 일정은 보고서 제출, 출장.
        app.buttons["calendar.day.2026-10-30"].tap()
        let dayBar = app.navigationBars["10월 30일 (금)"]
        XCTAssertTrue(dayBar.waitForExistence(timeout: 5))
        // 시트를 크게 올린다. 막대를 끌면 목록은 스크롤되지 않고 시트만 커진다.
        dayBar.swipeUp()

        let timeline = element("dayDetail.timeline", in: app)
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        for title in ["세미나", "병원", "저녁 약속"] {
            XCTAssertTrue(timeline.staticTexts[title].waitForExistence(timeout: 5), "\(title) 는 타임라인 안에 있어야 한다")
        }
        XCTAssertFalse(timeline.staticTexts["보고서 제출"].exists, "종일 일정은 타임라인에 넣지 않는다")
        // 세미나에는 본문이 있다. 본문 버튼은 누르기 쉬운 크기다(사용자 요청 2026-10-21).
        let bodyButton = timeline.buttons["dayDetail.body"]
        XCTAssertTrue(bodyButton.waitForExistence(timeout: 5), "본문이 있는 블록에 본문 버튼이 있어야 한다")
        XCTAssertGreaterThanOrEqual(bodyButton.frame.width, 30, "타임라인의 본문 버튼은 30pt 이상이어야 한다")
        attachScreenshot(of: app, named: "31-day-timeline")

        // 병원(15:00–16:00) 오른쪽 빈 곳의 15:45를 누르면 15:30부터 새 일정이 열린다.
        let list = element("dayDetail.list", in: app)
        let target = visiblePoint(inTimeline: timeline, hoursFromTop: 6.75, totalHours: 11, below: dayBar, scrolling: list, in: app)
        target.tap()
        let titleField = app.textFields["editor.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "빈 곳을 누르면 새 일정 화면이 열려야 한다")
        XCTAssertEqual(app.switches["시간 지정"].value as? String, "1", "타임라인에서 열면 시간 지정이 켜져 있어야 한다")
        titleField.tap()
        titleField.typeText("회의록 정리")
        app.buttons["저장"].tap()
        XCTAssertTrue(titleField.waitForNonExistence(timeout: 5), "저장하면 편집 화면이 닫혀야 한다")

        let note = timeline.staticTexts["회의록 정리"]
        XCTAssertTrue(note.waitForExistence(timeout: 5), "새 일정이 타임라인에 보여야 한다")
        XCTAssertTrue(labelContaining("3:30", in: timeline).exists, "누른 곳의 30분 단위 시각부터 시작해야 한다")
        XCTAssertGreaterThan(note.frame.minX, timeline.staticTexts["병원"].frame.minX + 20, "겹치는 일정은 옆 열에 놓여야 한다")
        attachScreenshot(of: app, named: "32-day-timeline-added")

        // 시간이 없는 일정은 타임라인 아래 목록에 있다.
        let report = list.staticTexts["보고서 제출"]
        scrollUntilVisible(report, in: app)
        XCTAssertTrue(list.staticTexts["출장"].exists, "종일·기간 일정은 타임라인 아래 목록에 있어야 한다")
    }

    /// 타임라인 오른쪽 빈 곳(블록이 없는 16pt 여백)의 위에서 `hoursFromTop` 시간 지점.
    /// 가로 위치는 타임라인 행 셀의 오른쪽 끝(행 안쪽 여백 8pt)에서 잰다. 접근성 묶음의 너비는 안의 요소에 따라 좁아질 수 있어서다.
    /// 그 지점이 화면 밖이거나 막대 아래에 가려지면 목록을 밀어 올린다.
    @MainActor
    private func visiblePoint(
        inTimeline timeline: XCUIElement,
        hoursFromTop: CGFloat,
        totalHours: CGFloat,
        below bar: XCUIElement,
        scrolling list: XCUIElement,
        in app: XCUIApplication
    ) -> XCUICoordinate {
        let row = list.cells.containing(.any, identifier: "dayDetail.timeline").firstMatch
        func point() -> XCUICoordinate {
            let grid = timeline.frame
            let x = row.exists ? row.frame.maxX - 16 : grid.maxX - 8
            let y = grid.minY + grid.height * hoursFromTop / totalHours
            return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
        }
        func isVisible(_ point: XCUICoordinate) -> Bool {
            point.screenPoint.y > bar.frame.maxY + 10 && point.screenPoint.y < app.windows.firstMatch.frame.maxY - 60
        }
        for _ in 0..<3 where !isVisible(point()) {
            list.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(isVisible(point()), "타임라인의 누를 곳이 화면 안에 있어야 한다")
        return point()
    }
}
