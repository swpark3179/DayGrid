# DayGrid

iOS 전용 개인 일정 앱이다(SwiftUI + SwiftData, iOS 18+). 전체 계획과 단계별 현황은 `docs/ROADMAP.md`에 있다. 작업을 시작하기 전에 해당 Phase를 먼저 읽는다.

## 개발 환경
- Mac이 없다. Xcode 빌드, 앱 테스트, 스크린샷은 GitHub Actions macOS 러너에서만 돌린다. 실기기 확인은 TestFlight로 한다.
- `*.xcodeproj`는 커밋하지 않는다. 프로젝트 정의는 `project.yml`(XcodeGen)만 고친다.
- 날짜와 규칙 로직은 `Packages/DayGridCore`(Foundation만 사용)에 두고 `swift test --package-path Packages/DayGridCore`로 검증한다. 이 패키지에 UIKit, SwiftUI, SwiftData를 import하지 않는다.

## 명령
- Core 테스트: `swift test --package-path Packages/DayGridCore`
  - 이 클라우드 세션은 네트워크 정책 때문에 download.swift.org에 접근할 수 없어서, 로컬에 Swift를 설치할 수 없다.
  - 그래서 CI에서 실행한다. ubuntu 잡은 `swift:6.2-noble` 컨테이너를 쓰고, macOS 잡도 같은 테스트를 돌린다.
- 앱(CI macOS 러너): `xcodegen generate` → `xcodebuild test -project DayGrid.xcodeproj -scheme DayGrid -destination id=<시뮬레이터 UDID> CODE_SIGNING_ALLOWED=NO`
- 스크린샷: UI 테스트가 `XCTAttachment(lifetime: .keepAlways)`로 남기면, CI가 `screenshots` 아티팩트로 올린다. 이름은 `NN-화면` 형식으로 붙인다.
- 앱 아이콘: `python3 scripts/make_app_icon.py DayGrid/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
- 음력 표: `pip install korean_lunar_calendar==0.4.0` → `python3 scripts/make_lunar_table.py > Packages/DayGridCore/Sources/DayGridCore/KoreanLunarData.swift`. `KoreanLunarData.swift`는 직접 고치지 않는다.
- 선거일과 임시공휴일: `DayGrid/Resources/holidays/KR-overrides.json`에 더하고 `version`을 올린다. 앱이 main 브랜치의 이 파일을 하루에 한 번까지 받아 온다.
- 본문 미리보기 JS(markdown-it, DOMPurify): `scripts/vendor_markdown.sh`로만 갱신한다. 버전은 스크립트 안에 고정돼 있다. `DayGrid/Resources/markdown/`은 폴더 참조로 번들에 들어간다(`project.yml`).
- CloudKit 스키마: `.github/workflows/cloudkit-schema.yml`을 수동 실행한다(mode `check`: 보기만, `import`: Development에 넣기). 필요한 Secret은 `CLOUDKIT_MANAGEMENT_TOKEN`, `APPLE_TEAM_ID`다. Production 배포는 사용자가 CloudKit Console에서 한다.
- TestFlight: `.github/workflows/testflight.yml`을 수동 실행한다(`main` 브랜치). 서명 없이 아카이브하고, API 키 클라우드 서명으로 내보내면서 업로드한다. 필요한 GitHub Secrets와 사용자 준비는 `docs/TESTFLIGHT.md`에 있다. API 키 값은 저장소나 채팅에 남기지 않는다.

## 규칙
- 종일/기간 일정, 휴일, 생일은 `LocalDate`(yyyymmdd)로 다룬다. 시간 일정만 `Date`를 쓴다.
- 음력은 Core `KoreanLunarCalendar`(한국천문연구원 기준 표)로만 계산한다. `Calendar(identifier: .chinese)`는 한국 음력과 날짜가 다를 수 있어 쓰지 않는다.
- 반복 할일의 주기와 상태(완료/n일째/놓침)는 Core `Recurrence`로만 계산한다. "오늘 해야 하는데 안 함"(배지, 위젯)은 `Recurrence.isDue`(`RecurringTask.isDue(on:)`)로 센다. 놓침은 저장하지 않는다. 체크는 `RecurringTask.toggleCompletion(of:today:in:)`로 해서 같은 주기에 기록이 둘 생기지 않게 한다.
- 알림은 Core `ReminderPlanner`로 계획하고 `NotificationScheduler.sync()`로만 예약한다. 알림 권한은 사용자가 알림을 켤 때만 묻는다(`requestAuthorization()`). 화면 코드에서 `UNUserNotificationCenter`를 직접 부르지 않는다.
- 공휴일은 Core `KoreanHolidays`가 계산하고, 앱에서는 `HolidayService`(보정 자료, 연도별 캐시)를 거쳐 쓴다. 날짜 칸 표시는 Core `DayMarks`로 모은다.
  - 공휴일(`DayMark.holidayNames`)과 개인 휴일(`personalHolidayNames`)은 따로 담는다.
  - 색은 `DayStyle`의 규칙을 따른다: 공휴일과 일요일은 빨강, 개인 휴일은 주황, 토요일은 파랑이다. 화면 코드에 색을 따로 쓰지 않는다.
- `Item`의 `startDayKey`/`endDayKey`는 yyyymmdd 정수이고 0이면 날짜 없음("나중에 할일")이다. 시간 일정에서는 조회용 색인일 뿐이므로, 표시할 날짜는 `calendarEntry(in:)`로 다시 계산한다.
- "나중에"로 보낼 때는 `unschedule()`이 아니라 `moveToInbox(order: Item.topInboxOrder(in:))`를 쓴다. 직전 일정의 모양(`ScheduleHint`)이 남아, 다시 날짜를 정할 때 기본값이 된다. 목록 순서는 `inboxOrder` 오름차순이다.
- 달력 배치 규칙(주 조각, 레인, "+N")은 `DayGridCore/MonthLayout.swift`에 있다. 화면 코드에서 배치를 다시 계산하지 않는다.
  - 화면 위치 → 날짜 칸은 `MonthLayout.day(atX:y:width:height:in:clamped:)`로만 구한다.
  - 달력에서 날짜를 꾹 누르면 기간 고르기(`RangePressGesture`)가 된다. 움직이지 않고 놓으면 그 날 새 일정이다. 날짜 칸에 `contextMenu`를 다시 달지 않는다.
  - 달력 격자의 탭과 꾹 누르기는 `DayPressRecognizer`(`RangePressGesture`) 하나가 받는다.
    - 날짜 칸(`DayHitTarget`)은 `Button`이 아니라 접근성 요소다.
    - 격자 안에 SwiftUI 버튼이나 제스처를 더하지 않는다. SwiftUI는 자식 제스처를 먼저 주므로, 꾹 누르기가 시작되지 못한다.
  - 꾹 누르는 동안은 손가락 아래 스크롤 뷰(달 넘김)를 멈춘다.
  - "나중에" → 달력 끌기
    - 데이터는 앱 안 전용 형식 `InboxDragPayload.type`으로 싣는다(`Info.plist`의 `UTExportedTypeDeclarations`).
    - 놓을 항목 id는 `CalendarDropState`에서 꺼낸다.
    - 놓으면 `item.schedule(on:using: item.scheduleHint)`로 넣는다.
- 모델 이름에 `Category`를 쓰지 않는다. Objective-C 런타임 타입과 겹치므로 `ItemCategory`를 쓴다.
- SwiftData 모델은 CloudKit 호환으로 만든다. 모든 속성에 기본값을 주거나 optional로 두고, 관계는 optional로 둔다. `@Attribute(.unique)`는 쓰지 않는다.
- iCloud 동기화(Phase 9)
  - 컨테이너는 `iCloud.io.github.swpark3179.DayGrid`다(`AppModelContainer.cloudKitContainerID`, `DayGrid/DayGrid.entitlements`). 사용자 준비는 `docs/ICLOUD.md`에 있다.
  - 모델을 더하거나 속성을 바꾸면 `cloudkit/DayGrid.ckdb`도 바꾼다. `CloudKitSchemaTests`가 실패 메시지로 새 내용을 보여준다. `.ckdb`는 Core `CloudKitSchemaFile`이 만든 그대로 둔다.
    - 머지한 뒤에는 "CloudKit schema" 워크플로(import)를 실행하고, 사용자가 Production에 배포한 다음에 TestFlight를 올린다.
    - Production에 배포한 필드는 이름을 바꾸거나 지우거나 타입을 바꾸지 않는다. 더하기만 한다.
  - 테스트는 iCloud를 쓰지 않는다. UI 테스트(`-UITestSeedData`)와 단위 테스트 호스트는 `LaunchOptions.usesCloudSync`가 false다.
  - 동기화로 생긴 중복(같은 `id`의 카테고리, 같은 주기의 완료 기록)은 `DuplicateMerger`로만 합친다.
  - 동기화 상태 문구는 Core `CloudSyncState`가 정한다. `CKContainer`는 부르지 않는다. entitlements가 없는 빌드에서는 앱이 꺼진다.
- UI 문자열은 한국어로 쓴다. 주 시작 요일 기본값은 일요일이다.
- UI 테스트는 실행 인자(`-UITestFixedToday`, `-UITestSeedData`)로 날짜와 데이터를 고정해서, 항상 같은 스크린샷이 나오게 한다.
- UI 테스트에서 찾는 요소에는 `accessibilityIdentifier`를 붙인다. 화면 뒤의 달력에도 같은 제목이 보이므로, 시트 안의 텍스트는 목록 식별자 아래에서 찾는다.
  - 지금 쓰는 식별자: `calendar.day.yyyy-MM-dd`, `calendar.add`, `dayDetail.list`, `dayDetail.add`, `editor.title`, `editor.delete`, `inbox.input`, `inbox.list`, `assign.today`/`assign.tomorrow`/`assign.weekend`, `assign.save`, `editor.body`, `body.mode`, `body.editor`, `body.preview`, `calendar.birthdays`, `birthdays.add`, `person.name`, `recurring.list`, `recurring.add`, `recurring.title`, `birthdays.list`, `holidays.list`, `settings.sync`, `calendar.monthTitle`, `monthPicker.year`/`monthPicker.previousYear`/`monthPicker.nextYear`/`monthPicker.month.N`, `dayDetail.body`, `reader.title`, `reader.category`, `reader.complete`
  - 실행 인자 `-UITestQuickAction addTask`는 홈 화면 퀵 액션으로 연 것처럼 시작한다.
- 시트를 닫은 뒤에는 `waitForNonExistence`로 닫힌 것을 확인하고 다음 조작을 한다. 닫히는 중인 시트 위로 탭이 들어가면 엉뚱한 버튼이 눌린다.
- UI 테스트 도우미(`launchApp`, `drag`, `tabButton`, `attachScreenshot`, `element(_:in:)`)는 `DayGridUITests/UITestSupport.swift`에 있다. 새 테스트 파일도 이것을 쓴다.
  - 스크린샷 번호: `ScreenshotTests` 01–15, `FeatureScreenshotTests` 16–25, `CalendarExtrasTests` 26–27, `DragTests` 28–29. 새 화면은 30부터 붙인다.
  - 도우미 `labelContaining(_:in:)`, `scrollUntilVisible(_:in:)`도 `UITestSupport.swift`에 있다.
  - 버튼 행(생일, 개인 휴일 목록)은 안의 글자가 라벨 하나로 합쳐질 수 있다. 정확한 글자 대신 `label CONTAINS`로 찾는다.
  - iOS 26 탭 막대의 배지 숫자는 접근성 트리에 나오지 않는다. 배지는 UI 테스트로 검사하지 않고, 개수는 단위 테스트로 확인한다.
- 목록 행을 밀 때는 텍스트에서 `swipeLeft()`를 하지 말고, 셀 좌표로 끈다. `drag(_:from:to:)`를 쓰고, 왼쪽으로 밀 때는 85% → 15%, 오른쪽으로 밀 때는 15% → 85%로 끈다. 작은 텍스트에서 밀면 끄는 거리가 짧아 탭으로 처리된다.
  - 끝까지 끌면 첫 번째 동작이 전체 밀기로 바로 실행될 수 있다. 버튼이 나타나면 누르고, 결과(행이 사라짐 등)로 확인한다.
  - 폼 아래쪽 요소(편집 화면의 삭제 버튼 등)는 화면 밖이면 접근성 트리에 없다. 스크롤하거나 화면 안의 요소로 확인한다.
- CI가 실패하면 "Show test failures" 단계(`xcresulttool get test-results summary`)와 "Export screenshots" 단계의 UI 계층 출력에서 원인을 본다.
- 편집 화면은 `ItemDraft`(값 타입)를 고치고, 저장할 때만 `apply(to:)`로 모델에 반영한다.
- 마크다운 서식 변환은 Core `MarkdownFormatter`(UTF-16 범위)가 한다. 화면 코드에서 문자열을 직접 고치지 않는다. 목록 행의 첫 줄은 `MarkdownSummary.firstLine(of:)`로 구한다.
  - 미리보기의 체크리스트 누르기는 Core `MarkdownTaskList.toggle(at:in:)`로 원문을 고친다.
  - `preview.js`의 체크 번호(`data-task-index`)와 Core의 체크 찾기 규칙은 같아야 한다. 한쪽을 바꾸면 다른 쪽도 바꾼다.
- 지금은 CI 결과를 기다리지 않고 진행한다(사용자 결정). 미룬 확인 항목은 `docs/ROADMAP.md`의 "나중에 할 테스트"에 적는다.
- 실기기 확인 항목은 `docs/DEVICE_CHECKLIST.md`에 모은다. 새 기능의 기기 확인도 여기에 더한다.
