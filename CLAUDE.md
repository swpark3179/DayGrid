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

## 규칙
- 종일/기간 일정, 휴일, 생일은 `LocalDate`(yyyymmdd)로 다룬다. 시간 일정만 `Date`를 쓴다.
- `Item`의 `startDayKey`/`endDayKey`는 yyyymmdd 정수이고 0이면 날짜 없음("나중에 할일")이다. 시간 일정에서는 조회용 색인일 뿐이므로, 표시할 날짜는 `calendarEntry(in:)`로 다시 계산한다.
- 달력 배치 규칙(주 조각, 레인, "+N")은 `DayGridCore/MonthLayout.swift`에 있다. 화면 코드에서 배치를 다시 계산하지 않는다.
- 모델 이름에 `Category`를 쓰지 않는다. Objective-C 런타임 타입과 겹치므로 `ItemCategory`를 쓴다.
- SwiftData 모델은 CloudKit 호환으로 만든다. 모든 속성에 기본값을 주거나 optional로 두고, 관계는 optional로 둔다. `@Attribute(.unique)`는 쓰지 않는다.
- UI 문자열은 한국어로 쓴다. 주 시작 요일 기본값은 일요일이다.
- UI 테스트는 실행 인자(`-UITestFixedToday`, `-UITestSeedData`)로 날짜와 데이터를 고정해서, 항상 같은 스크린샷이 나오게 한다.
