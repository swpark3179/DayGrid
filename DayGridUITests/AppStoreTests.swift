import XCTest

/// App Store에 올릴 화면과 미리보기 영상을 만든다. 보통 CI에서는 건너뛴다.
///
/// - "App Store assets" 워크플로(`.github/workflows/appstore-assets.yml`)가 `TEST_RUNNER_DAYGRID_APPSTORE=1`로 켠다.
///   xcodebuild는 `TEST_RUNNER_`로 시작하는 환경 변수를 앞부분을 떼고 테스트 실행기에 넘긴다.
/// - 스크린샷 이름은 `appstore/screenshots.json`의 `raw`와 같다. CI 스크린샷 번호(01–41…)와는 따로 센다.
/// - 영상은 시뮬레이터 밖의 `scripts/appstore/record_previews.py`가 녹화한다. 둘은 파일로 신호를 주고받는다(`PreviewRecorder`).
enum AppStoreRun {
    static var environment: [String: String] { ProcessInfo.processInfo.environment }

    static var isEnabled: Bool { environment["DAYGRID_APPSTORE"] == "1" }

    static func skipUnlessEnabled() throws {
        try XCTSkipUnless(isEnabled, "App Store assets 워크플로에서만 실행한다(TEST_RUNNER_DAYGRID_APPSTORE=1)")
    }

    /// 화면이 자리를 잡을 때까지 기다린다. 영상에서는 보는 사람이 따라올 시간이다.
    static func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}

/// 스크린샷 9장(01–09). 화면마다 앱을 새로 띄워 하나가 실패해도 나머지는 남는다.
final class AppStoreScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        try AppStoreRun.skipUnlessEnabled()
        continueAfterFailure = false
    }

    @MainActor
    private func launchCalendar(extraArguments: [String] = []) -> XCUIApplication {
        let app = launchApp(extraArguments: extraArguments)
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["주간 회의"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String, settle: TimeInterval = 1.0) {
        AppStoreRun.pause(settle)
        attachScreenshot(of: app, named: name)
    }

    @MainActor
    func test01Calendar() throws {
        let app = launchCalendar()
        capture(app, "01-calendar")
    }

    @MainActor
    func test02DayDetail() throws {
        let app = launchCalendar()
        app.buttons["calendar.day.2026-10-19"].tap()
        XCTAssertTrue(app.navigationBars["10월 19일 (월)"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("dayDetail.list", in: app).staticTexts["은행 업무"].waitForExistence(timeout: 5))
        capture(app, "02-day-detail")
    }

    /// 타임라인은 시트를 크게 올려서 찍는다. 반쯤 열린 시트는 뒤의 달력이 비쳐 블록이 흐리게 보인다.
    @MainActor
    func test03Timeline() throws {
        let app = launchCalendar(extraArguments: ["-dayDetailStyle", "timeline"])
        app.buttons["calendar.day.2026-10-19"].tap()
        let dayBar = app.navigationBars["10월 19일 (월)"]
        XCTAssertTrue(dayBar.waitForExistence(timeout: 5))
        let timeline = element("dayDetail.timeline", in: app)
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        AppStoreRun.pause(0.8)
        dayBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)),
                withVelocity: .default,
                thenHoldForDuration: 0.1
            )
        XCTAssertTrue(timeline.staticTexts["주간 회의"].waitForExistence(timeout: 5))
        capture(app, "03-timeline", settle: 1.5)
    }

    @MainActor
    func test04Inbox() throws {
        let app = launchCalendar()
        tabButton("나중에", in: app).tap()
        XCTAssertTrue(app.navigationBars["나중에"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("inbox.list", in: app).staticTexts["책 반납하기"].waitForExistence(timeout: 5))
        capture(app, "04-inbox")
    }

    @MainActor
    func test05Recurring() throws {
        let app = launchCalendar()
        tabButton("반복", in: app).tap()
        XCTAssertTrue(app.navigationBars["반복"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("recurring.list", in: app).staticTexts["관리비 납부"].waitForExistence(timeout: 5))
        capture(app, "05-recurring")
    }

    /// 알림 칩은 누르지 않는다. 알림 권한 창이 떠서 화면을 가린다.
    @MainActor
    func test06Editor() throws {
        let app = launchCalendar()
        app.buttons["calendar.day.2026-10-19"].tap()
        XCTAssertTrue(app.navigationBars["10월 19일 (월)"].waitForExistence(timeout: 5))
        let meeting = element("dayDetail.list", in: app).staticTexts["주간 회의"]
        XCTAssertTrue(meeting.waitForExistence(timeout: 5))
        meeting.tap()
        XCTAssertTrue(app.navigationBars["일정 편집"].waitForExistence(timeout: 5))
        scrollUntilVisible(app.buttons["reminder.정시"], in: app)
        capture(app, "06-editor")
    }

    @MainActor
    func test07Birthdays() throws {
        let app = launchCalendar()
        let banner = app.buttons["calendar.birthdays"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        banner.tap()
        XCTAssertTrue(app.navigationBars["생일"].waitForExistence(timeout: 5))
        XCTAssertTrue(labelContaining("김민수", in: element("birthdays.list", in: app)).waitForExistence(timeout: 5))
        capture(app, "07-birthdays")
    }

    @MainActor
    func test08Body() throws {
        let app = launchCalendar()
        app.buttons["calendar.day.2026-10-28"].tap()
        XCTAssertTrue(app.navigationBars["10월 28일 (수)"].waitForExistence(timeout: 5))
        let trip = element("dayDetail.list", in: app).cells.containing(.staticText, identifier: "출장").firstMatch
        XCTAssertTrue(trip.waitForExistence(timeout: 5))
        trip.buttons["dayDetail.body"].tap()
        XCTAssertTrue(app.navigationBars["본문"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["부산 출장"].waitForExistence(timeout: 15))
        capture(app, "08-body", settle: 1.5)
    }

    @MainActor
    func test09DarkCalendar() throws {
        let app = launchCalendar(extraArguments: ["-appearance", "dark"])
        capture(app, "09-dark")
    }
}

/// 미리보기 영상 2개. 앱을 띄운 뒤 녹화를 시작하고, 사람이 쓰듯 천천히 움직인다.
/// App Store 미리보기는 15–30초여야 한다. 길이는 `scripts/appstore/encode_previews.py`가 맞춘다.
final class AppStorePreviewTests: XCTestCase {
    override func setUpWithError() throws {
        try AppStoreRun.skipUnlessEnabled()
        continueAfterFailure = false
    }

    /// 달력: 연·월로 다른 달 보기 → 꾹 눌러 기간 일정 만들기
    /// 녹화 중에는 밀어서 달을 넘기지 않는다. 러너가 바빠 손가락 움직임이 늦게 닿으면 꾹 누르기(0.4초)가 먼저 시작되어
    /// 달 넘김이 멈춘다(2026-11-01 실행 #1, #2). 연·월 고르기는 누르기만 하므로 시간에 흔들리지 않는다.
    @MainActor
    func test1CalendarPreview() throws {
        let recorder = try PreviewRecorder()
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["주간 회의"].waitForExistence(timeout: 15))
        AppStoreRun.pause(1.0)

        try recorder.start("1-calendar")
        AppStoreRun.pause(2.0)
        app.buttons["calendar.monthTitle"].tap()
        let pickerBar = app.navigationBars["날짜로 이동"]
        XCTAssertTrue(pickerBar.waitForExistence(timeout: 5))
        AppStoreRun.pause(1.0)
        app.buttons["monthPicker.month.11"].tap()
        XCTAssertTrue(pickerBar.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2026년 11월"].waitForExistence(timeout: 5))
        AppStoreRun.pause(1.5)
        app.buttons["오늘"].tap()
        XCTAssertTrue(app.staticTexts["2026년 10월"].waitForExistence(timeout: 5))
        AppStoreRun.pause(1.0)

        // 10/20을 꾹 눌러 10/23까지 끈다 → 새 일정
        app.buttons["calendar.day.2026-10-20"].press(
            forDuration: 1.0,
            thenDragTo: app.buttons["calendar.day.2026-10-23"],
            withVelocity: .slow,
            thenHoldForDuration: 0.5
        )
        let editorBar = app.navigationBars["새 일정"]
        XCTAssertTrue(editorBar.waitForExistence(timeout: 5))
        AppStoreRun.pause(0.8)
        let title = app.textFields["editor.title"]
        title.tap()
        title.typeText("제주 여행")
        AppStoreRun.pause(0.6)
        let family = app.buttons["category.가족"]
        if family.exists, family.isHittable {
            family.tap()
            AppStoreRun.pause(0.6)
        }
        app.buttons["저장"].tap()
        XCTAssertTrue(editorBar.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["제주 여행"].waitForExistence(timeout: 5))
        AppStoreRun.pause(2.5)
        try recorder.stop("1-calendar")
    }

    /// 할일: "나중에" 빠른 입력 → 꾹 눌러 달력에 넣기 → 반복 할일 체크
    @MainActor
    func test2TasksPreview() throws {
        let recorder = try PreviewRecorder()
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["주간 회의"].waitForExistence(timeout: 15))
        // 놓을 칸(10/14)의 화면 위치. 꾹 누르는 동안 "나중에" 목록 위에 거의 같은 자리의 달력이 덮인다(DragTests).
        let targetFrame = app.buttons["calendar.day.2026-10-14"].frame
        AppStoreRun.pause(1.0)

        try recorder.start("2-tasks")
        AppStoreRun.pause(1.5)
        tabButton("나중에", in: app).tap()
        let list = element("inbox.list", in: app)
        XCTAssertTrue(list.staticTexts["책 반납하기"].waitForExistence(timeout: 5))
        AppStoreRun.pause(1.2)

        let input = app.textFields["inbox.input"]
        input.tap()
        input.typeText("택배 보내기\n")
        XCTAssertTrue(list.staticTexts["택배 보내기"].waitForExistence(timeout: 5))
        AppStoreRun.pause(0.8)
        input.typeText("\n")
        AppStoreRun.pause(1.2)

        let row = list.cells.containing(.staticText, identifier: "책 반납하기").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let target = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: targetFrame.midX, dy: targetFrame.midY))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.0, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.6)
        XCTAssertTrue(app.buttons["calendar.add"].waitForExistence(timeout: 5), "달력에 넣으면 달력 탭으로 바뀌어야 한다")
        AppStoreRun.pause(2.5)

        tabButton("반복", in: app).tap()
        let recurring = element("recurring.list", in: app)
        XCTAssertTrue(recurring.staticTexts["물 2L 마시기"].waitForExistence(timeout: 5))
        AppStoreRun.pause(1.2)
        for title in ["물 2L 마시기", "헬스장"] {
            let check = recurring.cells.containing(.staticText, identifier: title).firstMatch.buttons["완료로 표시"]
            if check.waitForExistence(timeout: 3) {
                check.tap()
                AppStoreRun.pause(1.2)
            }
        }
        AppStoreRun.pause(1.5)
        try recorder.stop("2-tasks")
    }
}

/// 시뮬레이터 밖의 녹화기(`scripts/appstore/record_previews.py`)와 파일로 신호를 주고받는다.
/// 시뮬레이터 안의 테스트 실행기도 Mac의 파일을 읽고 쓸 수 있다.
///
/// 1. 테스트가 `<이름>.start`를 만든다. → 녹화기가 녹화를 시작하고 `<이름>.recording`을 만든다.
/// 2. 테스트가 `<이름>.stop`을 만든다. → 녹화기가 녹화를 끝내 파일을 저장하고 `<이름>.saved`를 만든다.
/// 테스트가 중간에 실패하면 `.stop`이 없으므로, 녹화기는 다음 `.start`나 `all.done`을 보고 그 녹화를 버린다.
struct PreviewRecorder {
    let directory: URL

    init() throws {
        let environment = AppStoreRun.environment
        if let path = environment["DAYGRID_APPSTORE_HANDSHAKE"], !path.isEmpty {
            directory = URL(filePath: path, directoryHint: .isDirectory)
        } else if let home = environment["SIMULATOR_HOST_HOME"] {
            directory = URL(filePath: home).appending(path: "Library/Caches/daygrid-appstore", directoryHint: .isDirectory)
        } else {
            throw XCTSkip("녹화기와 주고받을 폴더가 없다")
        }
    }

    /// simctl은 녹화를 시작하는 데 30초쯤 걸릴 수 있다(2026-11-01 실행 #1).
    func start(_ name: String) throws {
        try signal("\(name).start")
        try waitFor("\(name).recording", timeout: 120)
        AppStoreRun.pause(1.0)
    }

    func stop(_ name: String) throws {
        try signal("\(name).stop")
        try waitFor("\(name).saved", timeout: 60)
    }

    private func signal(_ file: String) throws {
        try Data().write(to: directory.appending(path: file))
    }

    private func waitFor(_ file: String, timeout: TimeInterval) throws {
        let path = directory.appending(path: file).path
        let deadline = Date().addingTimeInterval(timeout)
        while !FileManager.default.fileExists(atPath: path) {
            guard Date() < deadline else {
                throw NSError(domain: "PreviewRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(file)를 기다리다 시간이 지났다"])
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
}
