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
- 본문 미리보기 JS(markdown-it, DOMPurify): `scripts/vendor_markdown.sh`로만 갱신한다. 버전은 스크립트 안에 고정돼 있다. `DayGrid/Resources/markdown/`은 폴더 참조로 번들에 들어간다(`project.yml`).
- TestFlight: `.github/workflows/testflight.yml`을 수동 실행한다(`main` 브랜치). 서명 없이 아카이브하고, API 키 클라우드 서명으로 내보내면서 업로드한다. 필요한 GitHub Secrets와 사용자 준비는 `docs/TESTFLIGHT.md`에 있다. API 키 값은 저장소나 채팅에 남기지 않는다.

## 규칙
- 종일/기간 일정, 휴일, 생일은 `LocalDate`(yyyymmdd)로 다룬다. 시간 일정만 `Date`를 쓴다.
- `Item`의 `startDayKey`/`endDayKey`는 yyyymmdd 정수이고 0이면 날짜 없음("나중에 할일")이다. 시간 일정에서는 조회용 색인일 뿐이므로, 표시할 날짜는 `calendarEntry(in:)`로 다시 계산한다.
- "나중에"로 보낼 때는 `unschedule()`이 아니라 `moveToInbox(order: Item.topInboxOrder(in:))`를 쓴다. 직전 일정의 모양(`ScheduleHint`)이 남아, 다시 날짜를 정할 때 기본값이 된다. 목록 순서는 `inboxOrder` 오름차순이다.
- 달력 배치 규칙(주 조각, 레인, "+N")은 `DayGridCore/MonthLayout.swift`에 있다. 화면 코드에서 배치를 다시 계산하지 않는다.
- 모델 이름에 `Category`를 쓰지 않는다. Objective-C 런타임 타입과 겹치므로 `ItemCategory`를 쓴다.
- SwiftData 모델은 CloudKit 호환으로 만든다. 모든 속성에 기본값을 주거나 optional로 두고, 관계는 optional로 둔다. `@Attribute(.unique)`는 쓰지 않는다.
- UI 문자열은 한국어로 쓴다. 주 시작 요일 기본값은 일요일이다.
- UI 테스트는 실행 인자(`-UITestFixedToday`, `-UITestSeedData`)로 날짜와 데이터를 고정해서, 항상 같은 스크린샷이 나오게 한다.
- UI 테스트에서 찾는 요소에는 `accessibilityIdentifier`를 붙인다. 화면 뒤의 달력에도 같은 제목이 보이므로, 시트 안의 텍스트는 목록 식별자 아래에서 찾는다.
  - 지금 쓰는 식별자: `calendar.day.yyyy-MM-dd`, `calendar.add`, `dayDetail.list`, `dayDetail.add`, `editor.title`, `editor.delete`, `inbox.input`, `inbox.list`, `assign.today`/`assign.tomorrow`/`assign.weekend`, `assign.save`, `editor.body`, `body.mode`, `body.editor`, `body.preview`
  - 실행 인자 `-UITestQuickAction addTask`는 홈 화면 퀵 액션으로 연 것처럼 시작한다.
- 시트를 닫은 뒤에는 `waitForNonExistence`로 닫힌 것을 확인하고 다음 조작을 한다. 닫히는 중인 시트 위로 탭이 들어가면 엉뚱한 버튼이 눌린다.
- 목록 행을 밀 때는 텍스트에서 `swipeLeft()`를 하지 말고, 셀 좌표로 끈다. `ScreenshotTests.drag(_:from:to:)`를 쓰고, 왼쪽으로 밀 때는 85% → 15%, 오른쪽으로 밀 때는 15% → 85%로 끈다. 작은 텍스트에서 밀면 끄는 거리가 짧아 탭으로 처리된다.
  - 끝까지 끌면 첫 번째 동작이 전체 밀기로 바로 실행될 수 있다. 버튼이 나타나면 누르고, 결과(행이 사라짐 등)로 확인한다.
  - 폼 아래쪽 요소(편집 화면의 삭제 버튼 등)는 화면 밖이면 접근성 트리에 없다. 스크롤하거나 화면 안의 요소로 확인한다.
- CI가 실패하면 "Show test failures" 단계(`xcresulttool get test-results summary`)와 "Export screenshots" 단계의 UI 계층 출력에서 원인을 본다.
- 편집 화면은 `ItemDraft`(값 타입)를 고치고, 저장할 때만 `apply(to:)`로 모델에 반영한다.
- 마크다운 서식 변환은 Core `MarkdownFormatter`(UTF-16 범위)가 한다. 화면 코드에서 문자열을 직접 고치지 않는다. 목록 행의 첫 줄은 `MarkdownSummary.firstLine(of:)`로 구한다.
- 지금은 CI 결과를 기다리지 않고 진행한다(사용자 결정). 미룬 확인 항목은 `docs/ROADMAP.md`의 "나중에 할 테스트"에 적는다.
