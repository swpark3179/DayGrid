# DayGrid: iOS 개인 일정 앱 개발 계획

## Context
- 목표: 앱을 켜면 바로 **월간 달력**이 보이고, 일정이 날짜 칸에 **카테고리 색상**으로 표시되는 iOS 전용 개인 일정 앱.
- 저장소 `swpark3179/DayGrid`는 README만 있는 빈 상태(public)라서 처음부터 만든다.
- 확정된 결정
  - 저장: SwiftData 로컬 저장부터 시작하고, iCloud(CloudKit) 동기화는 후반 단계에서 켠다. 모델은 처음부터 CloudKit 제약에 맞춘다.
  - 생일: iOS 연락처에서 가져오기(음력 포함)와 앱에서 직접 입력을 함께 지원한다.
  - 본문 편집기: 마크다운 소스 편집 + 미리보기(HTML 섞인 본문 허용).
  - 빌드 환경: **Mac 없음**. GitHub Actions macOS 러너에서 빌드·테스트·스크린샷을 만든다(public 저장소라 무료). 실기기 설치는 **유료 개발자 계정 + TestFlight**로 한다.
- "푸시 알림"은 서버 없이 **로컬 알림**(UNUserNotificationCenter)으로 구현한다. APNs 서버는 필요 없다.

## 기술 스택과 원칙
- Swift 6, SwiftUI, SwiftData, 최소 **iOS 18**. UI는 한국어, 주 시작 요일은 일요일(설정에서 변경 가능).
- **Xcode 프로젝트 파일은 커밋하지 않는다.** `project.yml`(XcodeGen)만 커밋하고, CI가 `xcodegen generate`로 만든다. Linux에서 `.pbxproj`를 직접 편집하는 위험을 없애기 위해서다.
- 날짜 계산 로직은 Foundation만 쓰는 SPM 패키지 `DayGridCore`로 분리한다. Linux(`swift test`)와 CI에서 빠르게 검증할 수 있다.
- 날짜 표현
  - 종일/기간 일정, 휴일, 생일은 시간대 영향을 받지 않는 `LocalDate`(yyyymmdd 정수)로 저장한다.
  - 시간 일정만 절대 시각 `Date`로 저장한다.
- SwiftData 모델의 CloudKit 호환 규칙: 모든 속성에 기본값을 주거나 optional로 둔다. 관계는 optional, `@Attribute(.unique)`는 쓰지 않는다. 식별자는 `UUID`로 한다.
- 단계마다 PR 1개를 만든다. CI가 green이어야 하고, UI 변경은 CI 스크린샷으로 확인한 뒤 머지한다.

## 저장소 구조 (목표)
```
project.yml                      # XcodeGen 스펙 (앱/테스트 타깃, Info.plist 키, entitlements)
DayGrid/                         # 앱 타깃
  App/        DayGridApp.swift, RootView (탭: 달력 · 나중에 · 반복 · 설정)
  Models/     SwiftData @Model (ItemCategory, Item, PersonalHoliday, Person, RecurringTask, RecurrenceCompletion)
  Features/   Calendar/, DayDetail/, ItemEditor/, Inbox/, Recurring/, Birthdays/, Settings/
  Services/   NotificationScheduler, ContactsImporter, HolidayProvider
  Resources/  holidays/KR.json, markdown/(preview.html, markdown-it, DOMPurify, style.css), Assets
Packages/DayGridCore/            # 순수 Swift: LocalDate, MonthGridLayout, RecurrenceEngine,
  Sources/ Tests/                #   BirthdayCalculator, HolidayCalendar, ReminderPlanner
DayGridTests/  DayGridUITests/   # 앱 단위 테스트(in-memory SwiftData), 스크린샷 UI 테스트
.github/workflows/ci.yml         # ubuntu: core 테스트 / macOS: 빌드 + 테스트 + 스크린샷
.github/workflows/testflight.yml # 수동 실행(태그나 workflow_dispatch) → TestFlight 업로드
scripts/fetch_holidays.py        # 공공데이터포털 특일정보 API → holidays/KR.json 생성
docs/ROADMAP.md, CLAUDE.md
```

## 핵심 데이터 모델
| 모델 | 주요 필드 | 비고 |
|---|---|---|
| `ItemCategory` | name, colorHex, sortOrder | 기본 카테고리를 고정 UUID로 시드한다. 나중에 iCloud 병합 시 중복을 막기 위해서다. |
| `Item` (일정 + 할일 통합) | title, body(markdown?), isTask(체크박스 여부), isAllDay, startDayKey/endDayKey(yyyymmdd, 0 = 날짜 없음), startDate/endDate(Date?), completedAt, category, reminderOffsets, inboxOrder, hintDayCount/hintStartMinute/hintDurationMinutes | **날짜가 없으면 "나중에 할일"**이다. 날짜를 배정하면 날짜 필드만 채우고, 보류하면 비운다. 보류할 때는 직전 일정의 모양(종일 일수, 시작 시각과 길이)을 hint 필드에 보관한다(Core `ScheduleHint`). |
| `PersonalHoliday` | name, startDay, endDay | 회사 휴가 같은 개인 휴일. 달력에서 공휴일처럼 표시한다. Phase 6에서 추가한다. |
| `Person` | name, month, day, year?, isLunar, isLeapMonth, contactIdentifier?, notifyDaysBefore | 연락처에서 가져온 사람과 직접 입력한 사람을 같은 모델로 다룬다. |
| `RecurringTask` | title, body?, category, rule(daily/weekly/monthly), weekdays[], dayOfMonth, startDay, endDay?, notifyMinutes(기본 09:00), isActive | |
| `RecurrenceCompletion` | task, occurrenceDay(해당 주기의 시작일), completedAt, completedDay | |

**반복 할일 규칙** (`RecurrenceEngine`, 단위 테스트로 고정)
- 주기 하나는 `[이번 발생일, 다음 발생일)` 구간이다. 이 구간 안에서 완료 기록이 없으면, 오늘 화면에 체크박스로 계속 남고 "n일째" 배지가 붙는다.
- 체크하면 `completedDay`(체크한 날)에 완료 표시가 나타난다. 반복 탭에는 규칙에 맞는 기간의 요약("이번 주 2/7", "이번 달 2/4", "올해 9/12")을 보여준다(Phase 20).
- 다음 주기가 오면 지난 주기는 "놓침"으로 판정한다. 놓침은 저장하지 않고 계산으로 구한다. 그리고 새 주기가 나타난다.
- 매월 31일처럼 없는 날짜는 그 달의 말일로 맞춘다. 매주는 여러 요일을 고를 수 있다. 매일은 하루가 주기 하나다.

## 단계별 작업

### Phase 0 — 기반과 CI (Mac 없이 빌드하는 파이프라인)
- `project.yml`, 빈 SwiftUI 앱(탭 4개 골격), `DayGridCore`와 `LocalDate`, 첫 테스트, `.gitignore`(`*.xcodeproj` 제외)를 만든다.
- `ci.yml`
  - ubuntu 잡: `swift test --package-path Packages/DayGridCore`
  - macOS 잡: xcodegen → `xcodebuild test`(iPhone 시뮬레이터) → UI 테스트 스크린샷을 `.xcresult`에서 PNG로 추출해 아티팩트로 업로드한다.
- 러너 이미지와 Xcode 버전은 착수 시점에 사용 가능한 최신 안정판으로 고정한다.
- `CLAUDE.md`에 빌드·테스트 명령, 구조, 날짜 규칙을 적는다. 클라우드 세션은 네트워크 정책 때문에 download.swift.org에 접근할 수 없어서, Core 테스트는 CI ubuntu 잡(`swift:6.2-noble` 컨테이너)에서 돌린다.
- UI 테스트는 `-UITestFixedToday 2026-10-19 -UITestSeedData` 같은 실행 인자를 받아, 고정된 날짜와 샘플 데이터로 항상 같은 스크린샷을 찍는다.
- **완료 기준:** CI green, 빈 앱 스크린샷이 아티팩트에 올라온다.

### Phase 1 — 데이터 모델과 달력 첫 화면
- 위 SwiftData 모델(이 단계에서는 ItemCategory, Item)과 기본 카테고리 시드, 설정의 카테고리 관리(이름, 색상), 주 시작 요일 설정을 만든다. `PersonalHoliday`는 실제로 쓰는 Phase 6에서 추가한다.
- `MonthGridLayout`(core)
  - 주 단위로 일정 구간을 잘라 막대로 만들고, 레인을 탐욕 배치한다. 시작이 빠르고 긴 일정이 먼저다.
  - 칸마다 최대 N줄까지 그리고 나머지는 "+N"으로 표시한다.
  - 여러 날에 걸친 시간 일정도 막대로 그린다.
- 월간 달력 화면
  - 좌우 스와이프로 월을 이동하고 "오늘" 버튼을 둔다.
  - 오늘을 강조하고 토요일과 일요일을 색으로 구분한다.
  - 종일/기간 일정은 색 막대, 시간 일정은 색 점과 제목으로 그린다.
- **완료 기준:** 레이아웃 단위 테스트(주를 넘는 일정, 겹침, +N)가 통과하고, 샘플 데이터 달력 스크린샷이 나온다.

### Phase 2 — 날짜 상세와 일정 편집
- 날짜를 탭하면 상세 화면(시트)이 열린다. 종일/기간 일정, 시간 일정, 할일을 섹션으로 나눠 보여준다(정렬 규칙은 Core `DayAgenda`). 공휴일·생일 표시는 Phase 6에서 상단에 붙인다.
- 편집기
  - 입력: 제목, 종일/시간 토글, 시작·종료(여러 날 가능), 카테고리, 할일 여부, 메모(평문, Phase 5에서 마크다운으로 확장)
  - 동작: 추가, 수정, 삭제, 복제
- 달력에서 `+` 버튼이나 날짜 길게 누르기로 바로 추가한다.
- **완료 기준:** CRUD가 앱을 다시 켜도 유지되고(앱 단위 테스트), 편집 흐름 UI 테스트가 통과한다.

### Phase 3 — TestFlight 배포 파이프라인 (실기기에서 처음 써보는 빌드)
- **사용자가 할 일**(먼저 시작해 두면 좋다)
  - Apple Developer Program 가입. 승인까지 최대 이틀쯤 걸린다.
  - App Store Connect에서 앱 레코드 생성(Bundle ID 결정).
  - App Store Connect API 키(Admin) 발급 후 GitHub Secrets에 등록.
- `testflight.yml`(수동 실행): macOS 러너에서 서명 없이 `xcodebuild archive`를 하고, `-exportArchive -allowProvisioningUpdates`와 API 키로 Apple 클라우드 배포 인증서 서명을 받아 바로 업로드한다(`ExportOptions.plist`의 `destination: upload`).
  - 아카이브 단계에서 자동 서명을 쓰면 깨끗한 러너마다 개발 인증서를 새로 만들어 한도에 걸린다. 그래서 아카이브는 서명하지 않는다.
  - 빌드 번호는 워크플로 실행 번호(`github.run_number`)를 쓴다.
  - 사용자 준비 절차는 `docs/TESTFLIGHT.md`에 있다.
  - CloudKit 같은 entitlement가 생기면(Phase 9) 서명 없는 아카이브로는 부족할 수 있다.
    - Phase 9에서는 ad-hoc 서명 단계에서 entitlements를 넣는 방식으로 먼저 시도한다.
    - 이 방식이 안 되면 개발 인증서 `.p12` Secret 방식으로 바꾼다.
- **완료 기준:** iPhone의 TestFlight 앱에서 설치하고 실행된다. 이후 단계는 기기에서도 확인한다.
- **결과(2026-10-19):** 첫 실행(빌드 1)에서 클라우드 서명과 업로드가 그대로 성공했다(사용자 확인). `.p12` 대안은 쓰지 않았다.
- **바뀜(2026-10-20, Phase 9 이후):** 클라우드 서명을 그만 쓰고, App Store Connect API로 실행마다 배포 인증서와 프로파일을 만든다(`scripts/ci/asc_signing.py`).
  - 이유: iCloud entitlements가 들어가자 Xcode 자동 서명이 `appstoreconnect.apple.com/xcbuild/v1/cloudContainers`에서 API 키로 401을 받았다. 그 결과 "No profiles"로 실패했다(실행 #3, #4).
  - 순서
    1. 인증서 키는 러너에서 만든다.
    2. 아카이브 안의 앱과 확장마다 App Store 프로파일을 만든다.
    3. App ID 기능과 프로파일 entitlements를 아카이브의 entitlements와 비교한다.
    4. 수동 서명으로 내보낸다.
    5. 마지막 단계에서 프로파일을 지우고 인증서를 폐기한다.
  - 정리하지 못한 "DayGrid CI" 프로파일과 그 인증서는 다음 실행이 먼저 지운다.
  - 워크플로 입력 `upload`를 끄면 서명까지만 하고, 최종 entitlements를 출력한다.
  - 확인(실행 #5, #6, 서명만): API로 인증서와 프로파일을 만들고 지우는 것까지 됐다.
    - 그런데 프로파일의 iCloud 컨테이너 목록이 비어 있었다(`icloud-container-identifiers: []`). App ID에 iCloud는 켜져 있지만 컨테이너가 연결되지 않은 것이다.
    - 사용자가 developer.apple.com에서 컨테이너를 체크한 뒤 다시 확인한다(`docs/ICLOUD.md` 2번).
    - Xcode 자동 서명이 `cloudContainers`를 부른 것도 이 연결을 하려던 것으로 보인다.

### Phase 4 — 나중에 할일(인박스): 배정과 보류
- "나중에" 탭
  - 상단 빠른 입력창: 엔터를 치면 바로 등록되고 연속으로 입력할 수 있다.
  - 목록 순서를 바꿀 수 있다.
  - 스와이프 동작: 날짜 배정, 완료, 삭제.
- 날짜 배정 시트: 오늘, 내일, 이번 주말, 날짜 선택 중에 고르고, 종일 또는 시간을 정한다. 보류 시 보관한 힌트를 기본값으로 쓴다.
- 보류: 날짜 상세에서 일정이나 할일을 스와이프해 "나중에 하기"를 누르면 인박스로 돌아간다.
- 할일은 달력과 상세 화면에서 체크박스로 보이고, 완료하면 취소선이 그어진다(상세 화면 체크와 달력 취소선은 Phase 2에서 먼저 넣었다).
- 홈 화면 아이콘 길게 누르기 퀵 액션 "할일 빠르게 추가"를 넣는다.
- **완료 기준:** 배정 → 달력 표시 → 보류 → 인박스 복귀 흐름의 UI 테스트가 통과한다.
- **구현 메모**
  - 날짜 고르기와 모양 기억은 Core에 있다: `QuickDay`(오늘, 내일, 이번 주말 = 토요일이고 주말이면 오늘), `ScheduleHint`.
  - 보류는 `Item.moveToInbox(order:)`가 맡는다. 날짜를 비우고 모양을 남기며, 완료 표시는 그대로 둔다. 다시 정할 때는 `Item.schedule(on:using:)`를 쓴다.
  - 편집 화면에 "날짜 지정" 토글을 넣었다. 끄고 저장하면 "나중에" 목록으로 간다. 인박스 항목을 편집해도 날짜가 생기지 않는다.
  - 목록 순서: `inboxOrder` 오름차순이다. 새 항목과 미룬 항목은 맨 위(`Item.topInboxOrder(in:)`)에 들어가고, 끌어서 옮기면 0, 1, 2…로 다시 매긴다.
  - 퀵 액션은 코드로 등록하는 동적 항목이라, 앱을 한 번 실행한 뒤부터 홈 화면에 나온다.

### Phase 5 — 상세 본문 (마크다운 + HTML)
- 한 줄 할일은 제목만 쓰면 된다. 본문은 선택 사항이다.
- 편집: `UITextView` 래퍼에 키보드 위 서식 툴바를 붙인다. 툴바는 제목, 굵게, 기울임, 목록, 체크리스트, 링크, 인용, 코드를 선택 영역에 감싸거나 삽입한다. 편집과 미리보기는 세그먼트로 전환한다.
- 미리보기
  - 번들에 넣은 `markdown-it`(html 허용, linkify, task-lists)과 `DOMPurify`로 WKWebView에서 오프라인 렌더링한다.
  - DOMPurify가 스크립트를 제거하고, 링크는 Safari로 연다.
  - 라이트/다크 CSS를 둔다.
- 목록 행에는 본문이 있음을 아이콘과 첫 줄 미리보기로 보여준다.
- **완료 기준:** 표, HTML 태그, 체크리스트가 들어간 본문 미리보기 스크린샷이 나온다.
- **구현 메모**
  - 서식 변환(감싸기, 줄 앞 표시, 링크)은 Core `MarkdownFormatter`가 한다. 범위는 UTF-16이고, 앱은 `UITextView.replace(_:withText:)`로 적용해 실행 취소가 된다.
  - 목록 행의 첫 줄은 Core `MarkdownSummary.firstLine(of:)`로 구한다.
  - 미리보기 리소스는 `DayGrid/Resources/markdown/`에 있다(markdown-it 14.1.0, DOMPurify 3.4.17). `scripts/vendor_markdown.sh`로만 갱신한다.
  - 체크리스트 규칙은 `preview.js`에 직접 넣었다. 처음 여는 file URL만 허용하고, 링크는 앱 밖에서 연다.
  - 편집 화면의 "메모"를 "본문" 화면(편집/미리보기 세그먼트)으로 바꿨다.

### Phase 6 — 공휴일, 개인 휴일, 생일
- 공휴일
  - `scripts/fetch_holidays.py`(공공데이터포털 특일정보 API, 키는 사용자가 제공)로 2025~2030년 `KR.json`을 만들어 번들에 넣는다.
  - 앱은 이 저장소의 raw JSON을 ETag 기반으로 가끔 갱신해 임시공휴일까지 반영한다. 별도 서버나 앱 내 API 키가 필요 없다.
- 달력에서 공휴일과 개인 휴일은 날짜 숫자를 빨간색으로 하고 이름을 표시한다. 개인 휴일(기간)은 `PersonalHoliday` 모델을 추가하고 편집 화면을 만든다.
- 생일
  - 가져오기: `ContactsImporter`가 `CNContactBirthdayKey`와 `CNContactNonGregorianBirthdayKey`를 읽는다. iOS 18의 제한 접근도 대응하고, 다시 가져올 때는 `contactIdentifier`로 갱신한다.
  - 직접 추가와 편집: 양력/음력, 윤달 여부를 입력한다.
  - 계산: `BirthdayCalculator`(core)가 음력을 올해 양력 날짜로 바꾼다. `.dangi`를 쓸 수 있으면 쓰고 아니면 `.chinese`로 대체하며, 알려진 설날·추석 날짜로 검증한다. 2월 29일과 윤달 생일은 평년 규칙을 따른다.
  - 표시: 달력에 🎂를 표시하고, 달력 상단 배너와 생일 목록에서 "다가오는 생일 D-n"(30일 이내)을 보여준다.
- **완료 기준:** 음력 변환과 휴일 파싱 단위 테스트가 통과하고, 휴일·생일 표시 스크린샷이 나온다.
- **구현 메모(사용자 결정: API 키 없이 "계산 + JSON 보정")**
  - 음력은 운영체제의 `.chinese`가 아니라 Core `KoreanLunarCalendar`를 쓴다.
    - 한국천문연구원 기준 표(`KoreanLunarData.swift`, 1900–2049년)를 `scripts/make_lunar_table.py`로 만든다(korean_lunar_calendar, MIT).
    - 중국 음력과는 해에 따라 하루씩 다르다. 예를 들어 2027년 설날은 한국 2월 7일, 중국 2월 6일이다.
    - 표로 계산한 결과를 1900–2050년 모든 날에 대해 원본 데이터와 양방향으로 대조했고, 모두 같았다.
  - 공휴일은 Core `KoreanHolidays`가 계산한다.
    - 양력과 음력 공휴일을 구한다.
    - 대체공휴일 규칙을 적용한다: 설날·추석은 일요일이나 다른 공휴일과 겹칠 때, 어린이날은 토·일요일이나 겹칠 때 생긴다. 국경일은 2021년부터, 부처님오신날과 성탄절은 2023년부터 같은 규칙을 따르고, 한 날에 공휴일이 겹치면 대체공휴일은 하나만 생긴다.
    - 2023–2030년을 공식 공휴일과 대조했다.
  - 선거일과 임시공휴일은 `DayGrid/Resources/holidays/KR-overrides.json`에 적는다.
    - 앱(`HolidayService`)은 앱에 넣은 파일을 쓰고, 하루에 한 번까지 main 브랜치의 같은 파일을 받아 온다. `version`이 더 높을 때만 바꾼다.
    - 새 임시공휴일이 생기면 이 파일에 더하고 `version`을 올린다.
  - 연락처 가져오기는 음력 생일(`nonGregorianBirthday`)이 있으면 그것을 쓰고, 다시 가져올 때는 `contactIdentifier`로 갱신한다.
  - 표시
    - 달력은 날짜 숫자를 빨갛게 하고 옆에 이름이나 🎂를 붙인다(Core `DayMarks`).
    - 하루 상세에는 "기념일" 섹션을 둔다.
    - 달력 위에 30일 안의 생일 배너를 띄운다.
    - 설정에 "기념일"(생일, 개인 휴일) 메뉴를 넣었다.

### Phase 7 — 반복 할일
- `RecurringTask`와 `RecurrenceCompletion` 모델, 그리고 `RecurrenceEngine`을 만든다. `RecurrenceEngine`은 발생일, 현재 활성 주기, 주기별 상태(완료/진행 중/놓침)를 계산한다.
- "반복" 탭에서 규칙을 만들고 편집한다. 매일, 매주(요일 여러 개), 매월(n일 또는 말일)을 지원한다.
- 오늘 날짜 상세에는 활성 주기 체크박스와 "n일째" 배지를 보여준다. 달력의 완료한 날에는 ✓를 찍고, 월 요약을 보여준다. 체크는 취소할 수 있다.
- **완료 기준:** 위 "반복 할일 규칙"의 경계 사례 단위 테스트가 통과한다. 경계 사례는 말일 보정, 주기가 넘어갈 때의 놓침 판정, 같은 주기 안의 중복 체크 방지다.
- **구현 메모**
  - Core `Recurrence`가 발생일, 날짜가 속한 주기, 상태(완료/n일째/놓침/예정), 월 요약을 계산한다.
  - 체크는 `RecurrenceToggle`로 정한다: 같은 주기에 기록이 있으면 지우고, 없으면 하나만 더한다.
  - 모델
    - `RecurringTask`는 규칙을 `ruleKind`, `weekdayMask`(1 << 요일), `monthDay`(0 = 말일)로 저장한다.
    - `RecurrenceCompletion`은 `cycleStartKey`와 `completedDayKey`를 저장한다.
    - 놓침은 저장하지 않는다.
  - 화면
    - "반복" 탭: 지금 주기를 체크하고, 이번 달 완료 수를 보여준다. 편집 화면에서는 매일, 매주(여러 요일), 매월(n일·말일)과 기간, 카테고리, 사용 여부를 정한다.
    - 하루 상세 아래쪽 "반복 할일" 섹션: 그날이 속한 주기를 보여주고, 지금 주기면 체크할 수 있다. (Phase 16에서 뺐다)
    - 달력: 반복 할일을 체크한 날에 ✓를 붙인다. (Phase 16에서 뺐다)
  - 알림 시각(`notifyMinute`)은 모델에만 있다. Phase 8에서 화면과 알림을 붙인다.

### Phase 8 — 알림 (미리알림)
- 알림 권한은 첫 알림을 설정하는 시점에 요청한다.
- 알림 종류
  - 일정·할일: 정시, 10분 전, 1시간 전, 하루 전(종일 일정은 당일 또는 전날 09:00).
  - 생일: 당일, n일 전.
  - 반복 할일: 주기가 시작되는 날 지정 시각에 **한 번**.
- `ReminderPlanner`(core)가 앞으로 30일 안의 알림 후보를 계산한다. iOS는 앱당 대기 알림을 64개까지만 허용하므로 가까운 순서로 최대 60개만 고른다.
- `NotificationScheduler`가 대기 중인 알림과 비교해 바뀐 것만 동기화한다. 동기화 시점은 앱 실행·포그라운드 진입, 데이터 변경, 하루 한 번 `BGAppRefreshTask`다.
- 알림에 "완료" 액션을 붙인다(할일, 반복 할일). 알림을 탭하면 해당 날짜로 이동한다.
- **완료 기준:** planner 단위 테스트(64개 제한, 반복 1회 알림)가 통과하고, TestFlight 기기에서 수동 체크리스트를 확인한다.
- **구현 메모**
  - Core `ReminderPlanner`가 앞으로 30일 안의 알림 후보를 만들고, 가까운 순으로 60개를 고른다. 식별자(`daygrid.…`)는 같은 알림이면 늘 같다.
  - 앱 `NotificationScheduler`는 대기 중인 알림과 시각·제목·내용을 비교해, 바뀐 것만 지우고 더한다.
    - 동기화 시점: 앱 실행, 포그라운드 진입, `ModelContext.didSave`(1초 모음), 하루 한 번 백그라운드 새로 고침(`.backgroundTask(.appRefresh)`).
    - 백그라운드 새로 고침에 필요한 배열 키는 `DayGrid/Info.plist`에 둔다.
  - 알림 권한은 사용자가 처음 알림을 켤 때만 묻는다. 권한이 없으면 동기화하지 않는다. 그래서 UI 테스트에는 영향이 없다.
    - 새 반복 할일은 알림을 끈 채로 시작한다. 처음에는 켠 채로 시작해서, 저장만 해도 권한을 물었다.
  - 알림 종류
    - 일정·할일: `Item.reminderMask`에 정시, 10분 전, 1시간 전, 하루 전을 둔다. 종일 일정은 당일 09:00과 전날 09:00이다.
    - 생일: 사람마다가 아니라 설정에서 한 번에 정한다(끔 / 당일 / 당일과 1·3·7일 전, 09:00).
    - 반복 할일: `notifyMinute`(음수면 끔)에 한 번 알린다. 완료한 주기는 알리지 않는다.
  - "완료" 동작: 할일은 완료로, 반복 할일은 그 주기를 완료로 표시한다(이미 완료면 그대로 둔다). 알림을 누르면 달력에서 그 날의 하루 상세가 열린다.

### Phase 9 — iCloud 동기화
- CloudKit 컨테이너 entitlement와 원격 알림 Background Mode를 추가하고, `ModelConfiguration(cloudKitDatabase: .private(...))`로 설정한다.
- 시드 카테고리 중복을 제거하는 병합 처리를 넣고, 동기화 상태를 설정 화면에 표시한다.
- **완료 기준:** 앱을 지웠다가 다시 설치해도 데이터가 복원된다. 기기가 2대면 양방향 반영도 확인한다.
- **현황(2026-10-20):** 사용자가 준비 단계(컨테이너, 토큰)를 마쳤고, 스키마를 Development에 import했다.
  - TestFlight 실행 #3(iCloud entitlements가 처음 들어간 빌드)이 내보내기에서 실패했다: `Authentication failed`, `No profiles for 'io.github.swpark3179.DayGrid' were found`.
  - 서명을 고친 뒤 체크리스트 7장을 확인한다.
  - TestFlight 실행 #9(빌드 9)가 올라갔다. 기기의 설정에 "동기화 오류: 작업을 완료할 수 없습니다. (CKErrorDomain 오류 2.)"가 보였다(사용자 확인).
    - 오류 2는 `partialFailure`다. 앱이 안쪽의 레코드별 오류를 찾지 못하고 바깥 문구만 보여줬다.
    - CloudKit schema 워크플로(check)에 Production 비교를 더해 확인했다. Production에는 `Users`만 있고 `CD_` 레코드 타입 6개가 없었다. Development import 뒤 Console의 Deploy를 하지 않은 것이다.
    - 할 일: 사용자가 CloudKit Console에서 Deploy Schema Changes → check로 확인 → 앱을 다시 열어 체크리스트 7장을 확인한다. 스키마는 앱 빌드와 상관없으므로 기존 빌드 9로도 확인할 수 있다.
  - 오류 읽기를 고쳤다: Core `CloudKitErrorReader`가 감싼 오류(`NSUnderlyingError`)와 레코드별 오류(`CKPartialErrors`)를 펼친다.
    - 덩달아 실패한 `batchRequestFailed`는 원인에서 뺀다.
    - 스키마 문제(`schemaMismatch`)와 컨테이너 설정 문제(`containerSetup`)는 따로 안내한다.
    - 그 밖의 오류는 코드 이름과 서버 문구를 보여준다.
    - 설정의 **오류 내용 복사**로 펼친 내용 전체를 복사할 수 있다.
  - TestFlight 빌드 10(2026-10-21)에서도 "iCloud 보내기 실패 … partialFailure(2)"가 보였다(사용자 확인).
    - 펼친 내용이 그 한 줄뿐이었다. 이벤트의 오류에 레코드별 오류가 들어 있지 않았다.
    - 같은 날 check(실행 #3, 03:31Z)에서도 Production에는 `Users`만 있었다. 원인은 그대로 Deploy를 하지 않은 것이다.
    - 할 일: 사용자가 CloudKit Console에서 Deploy Schema Changes → check로 확인 → 앱을 다시 열어 체크리스트 7장을 확인한다.
    - 앱도 고쳤다(Phase 14).
      - 안쪽 오류 없는 묶음 실패를 `unexplainedPartialFailure`로 따로 안내한다.
      - 실패하면 그 시각의 앱 기록(OSLogStore)을 읽어 원인을 찾고, 복사용 설명에 붙인다.
  - Phase 14 빌드(2026-10-21 06:38Z)의 앱 기록이 원인을 찾았다: `invalidArguments(12): Cannot create new type CD_PersonalHoliday in production schema ×2`(사용자 확인).
    - 앱은 이것을 `schemaMismatch`로 나눈다. 앱 쪽 고칠 것은 없다.
    - check(실행 #4, 09:36Z)에서도 Production에는 `Users`만 있었다. 할 일은 그대로 사용자가 Console에서 Deploy Schema Changes → check로 확인 → 앱을 다시 열어 체크리스트 7장을 확인하는 것이다.
- **구현 메모(사용자 결정: 스키마는 GitHub Actions로 자동 준비, 동기화는 항상 켬)**
  - TestFlight 빌드는 CloudKit **Production**을 쓴다.
    - Production 스키마는 자동으로 생기지 않는다. Development에 넣은 뒤 CloudKit Console에서 배포해야 한다.
    - 한 번 배포한 필드는 지우거나 타입을 바꿀 수 없다.
    - Mac이 없어 개발 빌드로 스키마를 만들 수 없으므로, 다음 순서로 준비한다.
      1. 모델에서 만든 `cloudkit/DayGrid.ckdb`를 커밋한다.
      2. `.github/workflows/cloudkit-schema.yml`(cktool)로 Development에 넣는다.
      3. 사용자가 Console에서 Production으로 배포한다.
    - 사용자 준비 단계는 `docs/ICLOUD.md`에 있다.
  - 스키마 파일
    - 렌더러는 Core `CloudKitSchemaFile`이다. Core Data 매핑을 따른다: `CD_` 접두어, `CD_entityName`, `CD_moveReceipt`, 문자열의 `_ckAsset`, to-one 관계는 STRING.
    - 앱 테스트 `CloudKitSchemaTests`는 `NSManagedObjectModel.makeManagedObjectModel(for:)`로 읽은 모델과 커밋된 파일이 같은지 검사한다. CloudKit 규칙(관계는 optional이고 반대쪽이 있음, unique 없음, deny 없음)도 함께 본다.
  - 저장소(`AppModelContainer`)
    - 보통 실행은 `.private("iCloud.io.github.swpark3179.DayGrid")`로 연다.
    - 열지 못하면 같은 파일을 `.none`으로 다시 열고, 이유를 설정에 보여준다.
    - 처음 켤 때 저장소 파일을 `Application Support/Backups/pre-icloud`에 한 번 복사해 둔다.
    - UI 테스트와 단위 테스트 호스트에서는 iCloud를 쓰지 않는다(`LaunchOptions.usesCloudSync`).
  - 상태
    - `CloudSyncMonitor`가 `NSPersistentCloudKitContainer.eventChangedNotification`을 듣고, Core `CloudSyncState`가 문구를 정한다.
    - 다른 기기의 변경을 받으면 `DuplicateMerger`로 중복을 합치고 알림을 다시 맞춘다.
  - 중복 병합(`DuplicateMerger`, 앱 시작과 가져오기 뒤)
    - 같은 `id`의 카테고리는 가장 먼저 만든 것을 남기고, 일정과 반복 할일을 옮긴다.
    - 같은 할일·같은 주기의 완료 기록은 가장 이른 체크만 남긴다.
  - TestFlight 워크플로는 서명 없이 아카이브한다. 그래서 ad-hoc 서명 단계에서 배포용 entitlements(`aps-environment=production`, `icloud-container-environment=Production`)를 넣고, 아카이브 안 앱에 iCloud 키가 있는지 검사한다.

### Phase 10 — 달력·본문 개선 (사용자 요청 2026-10-20)
- 달력 왼쪽 위 "2026년 10월"(또는 옆 화살표)을 누르면 연·월 이동 시트가 열린다. 연도를 넘기고 달을 고르면 바로 간다(범위는 오늘 ±10년).
- 개인 휴일은 **주황**, 공휴일과 일요일은 빨강, 토요일은 파랑이다(사용자 결정).
- "반복" 탭에 주기가 돌아왔는데 아직 하지 않은 반복 할일 수를 배지로 보인다.
- 하루 상세 행에 본문이 있으면 오른쪽에 본문 버튼이 생긴다. 누르면 읽기 화면(제목, 시간, 카테고리, 본문)이 열린다.
  - 그 화면에서 할일 완료와 본문 체크리스트를 켜고 끌 수 있다(사용자 결정: 둘 다).
- **완료 기준:** Core 테스트(DayMark, `Recurrence.isDue`, `MarkdownTaskList`)가 통과하고, 스크린샷 26–27이 나온다.
- **구현 메모**
  - Core `DayMark`
    - 공휴일(`holidayNames`)과 개인 휴일(`personalHolidayNames`)을 따로 담는다.
    - 같은 날에 둘 다 있으면 공휴일로 본다(`isPublicHoliday`/`isPersonalHoliday`).
    - 색은 `DayStyle.numberColor(for:mark:)`가 정한다.
  - 미완료 수는 Core `Recurrence.isDue(on:completedCycleStarts:)`로 센다. 위젯(Phase 12)도 같은 함수를 쓴다.
  - 본문 체크리스트
    - `preview.js`가 체크박스에 문서 순서대로 `data-task-index`를 붙이고, 읽기 화면에서 `enableTaskToggles()`로 누를 수 있게 한다.
    - 누르면 `MarkdownPreview(onToggleTask:)` → Core `MarkdownTaskList.toggle(at:in:)` 순서로 원문을 고친다.
    - 두 쪽의 체크 찾기 규칙(목록 표시, 인용, 펜스 코드 제외)이 같아야 한다. jsdom과 Python으로 같은 결과를 확인했다.

### Phase 11 — 끌어서 일정 넣기 (사용자 요청 2026-10-20)
- 달력에서 날짜를 꾹 누르면 끌기 모드가 된다.
  - 다른 날짜까지 끌고 놓으면 그 기간의 종일 일정을 만든다.
  - 움직이지 않고 놓으면 그 날 새 일정이다(예전 메뉴를 대신한다).
- "나중에" 탭에서 항목을 오래 누르면 달력으로 바뀌고, 손을 떼지 않고 날짜 위에 놓으면 그 날로 들어간다(사용자 결정: 끌어서 놓기).
  - 가장자리에 머무르면 이전·다음 달로 넘어간다.
- **완료 기준:** 위치 → 날짜 칸 계산(Core) 테스트가 통과하고, 기간 만들기 UI 테스트가 통과한다. 끌어서 놓기는 기기에서 확인한다.
- **구현 메모**
  - 위치 → 날짜: Core `MonthLayout.dayIndex`/`day(atX:…)`(7열 × 주 수, 같은 크기 칸)
    - 끌기 중에는 `clamped`로 격자 밖을 가장 가까운 칸에 맞춘다.
  - 꾹 눌러 기간 만들기
    - `RangePressGesture`(iOS 18 `UIGestureRecognizerRepresentable`)를 달력 페이지에 단다. UIKit 제스처 `DayPressRecognizer` 하나가 탭과 꾹 누르기를 모두 받는다.
      - 짧게 떼면 탭(하루 상세)이다.
      - 0.4초 동안 움직이지 않으면 기간 고르기다.
      - 그 전에 12pt 넘게 움직이면 실패해서 달 넘김에 양보한다.
    - 날짜 칸은 SwiftUI `Button`이 아니라 접근성 요소다(라벨, 버튼 특성, VoiceOver 실행 동작, `calendar.day.…` 식별자).
      - PR #15 CI에서 꾹 눌러 끌었더니 달이 9월로 넘어갔다(두 번).
      - 원인: SwiftUI는 자식 `Button`의 제스처를 부모 `.gesture`보다 먼저 준다. 그래서 꾹 누르기가 시작되지 못했다.
    - 기간 고르기가 시작되면 손가락 아래의 스크롤 뷰(달 넘김)를 끝날 때까지 멈춘다.
    - 날짜 칸의 `contextMenu`(이 날에 일정 추가)는 뺐다. 움직이지 않고 놓으면 같은 일을 한다.
    - 기간은 `ItemEditorView.Mode.newRange` → `ItemDraft.newAllDay(from:through:)`(종일)로 연다.
  - "나중에" → 달력
    - 행의 `.onDrag`가 `InboxDragPayload`(앱 안 전용 UTType)를 싣고, `CalendarDropState`에 항목 id를 넣은 뒤 달력 탭으로 바꾼다.
    - 달력 페이지의 `CalendarDropDelegate`가 손가락 아래 칸을 강조하고, 가장자리에 0.8초 머무르면 달을 넘긴다.
    - 놓으면 `schedule(on:using: scheduleHint)`로 넣는다. 날짜가 이미 있는 항목은 건너뛴다.
    - 순서를 바꾸는 편집 중이거나 완료한 항목은 끌지 않는다.

### Phase 12 — 잠금화면 위젯 (사용자 요청 2026-10-20)
- 주기가 돌아왔는데 아직 하지 않은 반복 할일을 보여주는 잠금화면 위젯을 만든다. 완료한 것은 숨긴다.
  - 모양: 목록형, 개수형, 한 줄형(사용자 결정: 모두)
- 앱이 App Group에 반복 할일 요약(JSON)을 쓰고, 위젯은 Core로 날짜마다 다시 계산한다. 위젯을 누르면 반복 탭이 열린다.
- 사용자 준비: App Group과 위젯 App ID 등록(`docs/WIDGET.md`).
- **완료 기준:** 요약 계산 테스트가 통과하고, 기기에서 위젯이 갱신되는지 확인한다.
- **구현 메모**
  - Core
    - `RecurringSnapshot`(Codable): 사용 중인 반복 할일의 id, 제목, `Recurrence`, 최근 62일의 완료한 주기 시작일
    - `pending(on:)`이 `Recurrence.isDue`로 그날 남은 것을 고른다.
    - `RecurrenceRule`과 `Recurrence`도 Codable이다.
  - 앱 `WidgetSnapshotWriter`
    - App Group(`group.io.github.swpark3179.DayGrid`) 폴더의 `recurring.json`에 쓰고 `WidgetCenter.reloadAllTimelines()`를 부른다.
    - 쓰는 시점: 앱 시작과 포그라운드 진입, 저장(1초 모음), iCloud에서 받은 뒤, 알림의 "완료" 뒤. 내용이 같으면 다시 그리지 않는다.
  - 위젯(`DayGridWidgets` 확장, `io.github.swpark3179.DayGrid.Widgets`)
    - 요약을 읽어 지금과 다음 3일 자정의 항목을 만든다. 앱을 열지 않아도 자정에 새 주기가 반영된다.
    - 모양: `accessoryRectangular`/`Circular`/`Inline`
    - 누르면 `daygrid://recurring` → 앱의 `AppRoute`가 반복 탭을 연다.
  - TestFlight 워크플로: 위젯 확장을 먼저, 앱을 다음에 ad-hoc 서명한다. 두 서명 모두 App Group 키가 있는지 검사한다.

### Phase 13 — 하루 상세 타임라인 (사용자 요청 2026-10-20)
- 설정의 "하루 상세" → 보기 방식에서 목록(지금과 같음)과 타임라인을 고른다. 타임라인이면 업무 시작·종료 시간도 정한다(기본 09:00–18:00).
- 타임라인 모양
  - 시간이 있는 일정과 할일을 업무 시간 격자의 시각 위치에 블록으로 놓는다(사용자 결정: 시간 할일도 넣음). 할일은 블록 안 체크박스로 완료한다.
  - 시간이 없는 종일·기간 일정, 할일, 반복 할일은 그 아래에 예전처럼 목록으로 보인다.
- 업무 시간 밖에 일정이 있으면, 그날만 그 시각까지 정시 단위로 범위를 넓힌다. 업무 시간 밖은 옅게 칠한다(사용자 결정).
- 겹치는 일정은 나란히 놓는다.
- 조작
  - 블록을 누르면 편집, 꾹 누르면 복제·나중에·삭제
  - 빈 곳을 누르면 그 시각(30분 단위)부터 1시간짜리 새 일정을 연다(사용자 결정). 현재 시각 선은 넣지 않는다.
- **완료 기준:** Core 테스트(`DayTimeline`, `DayAgenda` 타임라인 묶음)가 통과하고, 스크린샷 30–32가 나온다.
- **구현 메모**
  - Core `DayTimeline`이 배치를 모두 정한다.
    - 업무 시간 고치기, 범위(정시로 넓힘), 최소 30분 높이, 겹침 묶음의 열
    - 위치 → 분(`minute(atY:height:)`), 분 → 위치
  - 하루에 걸친 부분은 `DayTimeline.Input(start:end:on:)`이 자른다. 밤을 넘는 일정은 날마다 그 날 부분만 들어간다.
  - `DayAgenda.make(separatingTimed: true)`
    - 시간 할일과 여러 날에 걸친 시간 일정까지 모두 `timed`로 보낸다.
    - `spanning`과 `tasks`에는 종일인 것만 남는다.
  - 설정은 `AppSettings`의 `@AppStorage` 키다. 모델은 바뀌지 않으므로 CloudKit 스키마 작업은 없다. 기기마다 따로 저장된다.
  - `DayTimelineView`
    - 시간당 48pt다. 오른쪽에 16pt 빈 곳을 두어, 블록이 있는 시각에도 눌러서 겹치는 일정을 만들 수 있다.
    - 빈 곳을 누르면 `ItemEditorView.Mode.newTimed`를 연다(`ItemDraft.new(on:startMinute:)`).
  - UI 테스트는 실행 인자 `-dayDetailStyle timeline`(UserDefaults 인자 도메인)으로 켠다. 설정의 Picker를 눌러 바꾸지 않는다. 바꾸면 값이 시뮬레이터에 남아 다른 테스트의 하루 상세 스크린샷이 바뀐다.

### Phase 14 — 달력 막대, 하루 상세에서 옮기기, 동기화 진단 (사용자 요청 2026-10-21)
- 일정은 하루 안에 끝나는 시간 일정도 달력에 여러 날 일정처럼 색 막대로 그린다. 하루 안의 시간 할일은 예전처럼 색 점과 제목이다(해석: "일정으로 등록한 것" = 할일이 아닌 항목).
- 하루 상세에서 일정이나 할일을 꾹 누르면 옮기기가 된다.
  - 시트가 작아져 달력이 보인다.
  - 손가락을 떼지 않고 다른 날짜에 놓으면 그 날로 옮긴다. 가장자리에 머무르면 달이 넘어간다.
- 타임라인 보기의 본문 버튼을 크게 한다(아이콘 20pt, 누르는 곳 34pt).
- iCloud "partialFailure(2)"가 계속 보인다 → Phase 9 현황 참고(Production 미배포). 앱은 앱 기록에서 원인을 찾는다.
- **완료 기준:** Core 테스트(`CalendarEntry.style`, 로그 읽기)와 앱 단위 테스트(`Item.move(byDays:)`)가 통과하고, UI 테스트가 하루 상세에서 끌어 옮긴다(스크린샷 33).
- **구현 메모**
  - 달력 모양
    - Core `CalendarEntry`에 `isTask`를 더했다. `style`은 "할일이면서 하루 안의 시간 일정"일 때만 `.chip`이다.
    - 하루 상세의 "시간" 묶음은 예전 규칙 그대로 `isTimedWithinOneDay`로 나눈다.
  - 옮기기
    - 행의 탭과 꾹 누르기를 `WindowPressGesture` 하나가 받는다. 달력 격자와 같은 `DayPressRecognizer`이고, 위치는 창 좌표다. 예전 행의 `onTapGesture`는 뺐다.
    - 시스템 끌어 놓기(`onDrag`)를 쓰지 않았다. 시트 뒤 달력에 놓으려면 시트가 비켜야 하는데, 끌기를 시작한 행이 화면에서 빠지면 끌기가 끝날 수 있어서다(Phase 11 "나중에" 끌기의 원인 후보).
      - 대신 시트를 `.height(64)`로 내리고, 목록 높이는 그대로 고정해 행의 셀이 살아 있게 한다.
      - 시트의 끌어 내리기는 막는다(`interactiveDismissDisabled`).
    - 달력 쪽: 페이지마다 `CalendarPageAnchor`가 격자 뷰를 `CalendarDropState`에 등록한다. 손가락의 창 좌표가 들어 있는 페이지에서 `MonthLayout.day(atX:…)`로 날짜를 구한다.
    - 미리보기(제목, "→ 날짜")는 `ItemMoveSession`이 창 맨 위에 UIKit 뷰로 붙인다.
    - 16pt 넘게 움직이지 않았거나, 같은 날이거나, 달력 밖에서 놓으면 옮기지 않고 시트를 되돌린다.
    - 옮기기는 `Item.move(byDays:)`(연 날짜 → 놓은 날짜의 차이)다. `currentScheduleHint` + `schedule(on:using:)`이라 시각, 길이, 종일 일수가 그대로다.
  - 동기화 진단
    - `CloudKitErrorReader.report`가 `CKPartialErrors`의 개수를 키 목록에 쓴다. 묶음이 비었는지, 읽지 못했는지 구별할 수 있다.
    - 안쪽 원인이 없는 묶음 실패는 `CloudSyncFailure.unexplainedPartialFailure`다. 문구는 Production 배포부터 확인하게 한다.
    - 실패 이벤트가 오면 `CloudSyncLogReader`가 1초 뒤 이 프로세스의 기록(OSLogStore)에서 그 시각의 CloudKit·Core Data 줄을 읽는다.
      - Core `CloudKitErrorReader.failure(fromLog:)`가 기록에 찍힌 CKError 설명(`"Server Rejected Request" (15/2000); server message = "…"`)을 오류 값으로 되살린다. 그다음 같은 규칙으로 나눈다.
      - 찾은 원인은 `CloudSyncState.attachLog`가 넣는다. 원인을 몰랐던 실패만 바꾸고, 복사용 설명에 "앱 기록:"을 붙인다.

### Phase 15 — "나중에" 키보드, 꾹 눌러 달력에 넣기 다시 만들기 (사용자 요청 2026-10-21)
- "나중에" 입력창에 쓰는 중 빈 곳을 누르면 키보드가 내려간다.
- "나중에" 항목을 오래 눌러 달력에 넣기가 기기에서 동작하지 않았다(사용자 확인). 탭은 달력으로 바뀌지만 놓아도 들어가지 않았다.
  - 꾹 누르면 탭을 바꾸지 않고 목록 위에 달력을 덮는다. 손가락을 떼지 않고 날짜 위에서 떼면 그 날로 들어간다.
  - 넣은 뒤에는 달력 탭에서 그 달을 보여준다(사용자 결정).
- iCloud "Cannot create new type CD_PersonalHoliday in production schema" → Phase 9 현황 참고(Production 미배포, 앱 변경 없음).
- **완료 기준:** 앱 단위 테스트(`CalendarDropStateTests`: 창 좌표 → 날짜, 숨긴 페이지, 가장자리 넘기기)가 통과한다. UI 테스트에서 "나중에" → 달력 넣기(스크린샷 29, 기대 실패 없음)와 키보드 내리기가 통과한다.
- **구현 메모**
  - 원인: Phase 11의 시스템 끌어 놓기(`onDrag`)는 끌기를 시작하자마자 달력 탭으로 바꿨다. 탭이 바뀌면 끌기를 시작한 목록이 창에서 빠져 끌기가 끝난다(Phase 11 "나중에 할 테스트"의 두 번째 원인 후보).
  - 그래서 하루 상세에서 옮기기(Phase 14)와 같은 방식으로 바꿨다.
    - 행의 탭(편집)과 꾹 누르기를 `WindowPressGesture` 하나가 받는다. 누른 행은 끝까지 창에 남는다.
    - 꾹 누르면 `InboxCalendarOverlay`(연·월, 안내, 요일, 달 페이지)를 목록 위에 덮는다.
      - 누르기와 접근성은 받지 않는다.
      - 머리 줄 높이를 달력 탭과 비슷하게 두어 날짜 칸이 거의 같은 자리에 온다.
    - 미리보기와 놓을 날짜는 `ItemMoveSession`이 맡는다(원래 날짜 없음).
    - 놓으면 `schedule(on:using: scheduleHint)`로 넣고, `RootView`가 달력 탭으로 바꾼다. `CalendarTab`은 `monthToShow`로 그 달을 연다.
    - 16pt 넘게 움직이지 않았거나 달력 밖에서 떼면 그대로 둔다.
  - `CalendarPageAnchor`가 페이지의 달 넘기기(`onPage`)도 등록한다. 가장자리에 머무르면 손가락 아래 달력(달력 탭이나 덮개)을 넘긴다.
    - 예전의 전역 `CalendarDropState.onPage`는 뺐다.
    - 창에 있어도 숨겨진 페이지는 건너뛴다.
  - "나중에" 목록의 `onMove`는 편집 중에만 켠다. 편집 밖에서도 켜 두면 목록의 끌어 순서 바꾸기가 꾹 누르기와 겹친다.
  - 시스템 끌어 놓기 코드(`InboxDragPayload`, `CalendarDropDelegate`, `Info.plist`의 `UTExportedTypeDeclarations`)는 뺐다.
  - 키보드: `KeyboardDismissOnTap`이 입력창에 포커스가 있는 동안 창에 UIKit 탭 제스처를 단다.
    - 다른 제스처를 막지 않고 막히지도 않는다(`cancelsTouchesInView = false`, `canPrevent`/`canBePrevented` false).
    - 입력창(`UITextInput`) 안의 탭은 뺀다.
    - SwiftUI `onTapGesture`를 목록에 달면 입력창과 행 버튼까지 가로채서 쓰지 않았다.

### Phase 16 — 테마 설정, 달력 탭에서 반복 할일 빼기 (사용자 요청 2026-10-22)
- 설정에서 테마를 시스템, 라이트, 다크 중에 고른다(기본은 시스템).
- 반복 할일은 달력 탭에 보이지 않는다. 반복 탭만으로 충분하다(사용자 결정).
  - 빠지는 것: 날짜 칸의 ✓, 하루 상세의 "반복 할일" 섹션
  - 그대로인 것: 반복 탭, 탭 배지, 잠금화면 위젯, 알림
- **완료 기준**
  - Core 테스트(`DayMarks`에서 반복 할일 완료를 뺌)와 앱 단위 테스트(`AppSettingsTests`: 테마 값, 알림 누르기 경로)가 통과한다.
  - UI 테스트에서 다크 스크린샷 03·18과 설정 스크린샷 34가 나온다.
  - 달력 칸과 하루 상세에 반복 할일이 없다.
- **구현 메모**
  - 테마
    - `AppSettings.appearanceKey`(`AppAppearance`)로 정한다. 설정 맨 위 "화면" 섹션에서 고른다.
    - `WindowAppearance`(UIKit 뷰)가 이 값을 창의 `overrideUserInterfaceStyle`에 건다.
      - 창에 걸기 때문에 시트, 끌기 미리보기(`ItemMoveSession`), 본문 미리보기(WKWebView의 `prefers-color-scheme`)도 같이 바뀐다.
      - SwiftUI `preferredColorScheme`은 시스템(nil)으로 되돌릴 때 바로 돌아오지 않는 경우가 있어 쓰지 않았다.
    - UI 테스트의 다크 모드는 실행 인자 `-appearance dark`(UserDefaults 인자 도메인)로 켠다. 예전 `-UITestColorScheme dark`(`LaunchOptions.forcesDarkAppearance`)는 뺐다.
  - 반복 할일
    - Core `DayMark.completedRecurringCount`와 `DayMarks.make(recurringCompletions:)`를 뺐다. `MonthPageView`도 완료 기록을 조회하지 않는다.
      - "나중에" 덮개 달력도 `MonthPageView`를 쓰므로 함께 빠졌다.
    - `DayDetailView`의 "반복 할일" 섹션을 뺐다. 목록 보기와 타임라인 보기 모두 해당한다.
    - 반복 할일 알림을 누르면 예전에는 그 날의 하루 상세가 열렸다. 섹션이 빠졌으므로 이제 반복 탭을 연다.
      - `NotificationRouter.open(day:recurringTaskID:)` → `routeToOpen = .recurring`
      - `RootView`는 위젯 주소(`AppRoute`)와 같은 경로로 처리한다.
      - 다른 알림은 예전처럼 그 날의 하루 상세를 연다.

### Phase 17 — UI·모션 개선 (사용자 요청 2026-10-22)
- 디자인 검토(아티팩트 "DayGrid UI·모션 개선안")의 P1–P3 9개 항목을 모두 넣는다(사용자 결정).
- 꾹 누르기와 밀기는 보이지 않는 동작이다. 누르는 동안의 표시, 놓은 뒤의 확인, 되돌리기를 채운다.
  - P1
    - 꾹 누르기 충전 링과 기간 띠
    - 착지 펄스
    - 되돌리기 토스트
  - P2
    - 끌기 미리보기의 들어 올림, 빨려 들어감, 되돌아감
    - 체크 완료 피드백
    - 숨은 제스처 안내(TipKit)
  - P3
    - 달력 제목 숫자 전환, 먼 달에서 오늘로 바로 가기
    - 편집 화면 카테고리 색 칩
    - "나중에" 빠른 입력 행 들어오기
- 모델과 CloudKit 스키마는 바뀌지 않는다.
- **완료 기준**
  - Core 테스트(`LocalDate.koreanRangeText`)가 통과한다.
  - 앱 단위 테스트가 통과한다.
    - `ItemStoreTests`: 스냅샷으로 되살리기, 나중에 되돌리기
    - `CalendarDropStateTests`: 칸 프레임, 착지 덮어쓰기
    - `LaunchOptionsTests`: 팁
  - UI 테스트 `MotionTests`(스크린샷 35–37)가 통과한다.
  - 움직임은 기기 체크리스트 15장으로 확인한다.
- **설계와 다른 점**
  - 꾹 눌러 옮기기에는 토스트를 띄우지 않는다. 시트가 닫히므로 달력의 놓은 날이 빛나는 것으로 알린다.
  - "나중에"로 보낸 토스트의 버튼은 "보기" 대신 "실행 취소"다.
  - 취소선은 긋는 애니메이션 대신 색과 함께 바뀐다(SwiftUI `strikethrough`는 애니메이션되지 않는다).
- **구현 메모**
  - 공통
    - 짧은 움직임은 `.snappy`다.
    - 동작 줄이기(`accessibilityReduceMotion`, `UIAccessibility.isReduceMotionEnabled`)면 크기와 위치 변화를 빼고 투명도만 바꾼다.
    - 격자 안에 새로 그린 것은 누르기를 받지 않는다.
  - 충전 링
    - `DayPressRecognizer.onPressChange`는 손가락이 닿으면 창 좌표를, 끝나거나 실패하면 `nil`을 알린다.
      - 실패(달 넘김)는 손가락이 닿아 있어도 바로 알린다. `reset()`은 손을 뗄 때 오기 때문이다.
    - `MonthPageView`가 `CalendarDropState.day(atWindowPoint:)`로 날짜를 찾는다. `WeekRowView`의 `PressChargeRing`이 0.1초 뒤부터 0.3초 동안 찬다.
  - 기간 띠
    - `WeekRowView`의 `DayBand`가 강조 범위를 주마다 띠 하나로 그린다. 앞뒤 주로 이어지는 쪽은 평평하다.
    - 끌어 놓을 칸도 같은 띠다.
    - 손가락 위 문구는 Core `LocalDate.koreanRangeText(through:)`다.
  - 착지 펄스
    - 하루 상세 옮기기, "나중에" 넣기, "오늘"(먼 달에서 바로 이동, 연·월 시트의 오늘 포함)이 `CalendarDropState.land(itemID:days:)`를 부른다.
    - 1.5초 동안 `landing`이 남는다. 그동안 그려진 달 페이지가 한 번 빛난다(`LandingPulse`). 그 일정의 막대는 `LandingPop`(keyframe)으로 튀어 들어온다.
  - 끌기 미리보기
    - `ItemMoveSession.begin`이 0.92 크기에서 spring으로 들어 올린다.
    - 놓으면 `CalendarDropState.windowFrame(of:)`의 칸 중심으로 줄어들며 사라진다. 취소하면 시작한 자리로 돌아간다.
  - 체크: `CompletionCheckmark`(기호 바꾸기 + bounce + 완료일 때만 success 햅틱)를 할일, 반복 할일, 읽기 화면이 같이 쓴다.
  - 반복 탭 월 요약
    - 18pt 진행 링을 붙인다.
    - 글자 "이번 달 5/15"는 그대로 두고 숫자만 굴린다. UI 테스트가 글자로 찾기 때문이다.
  - 토스트
    - 상태는 `UndoToastState`(화면마다 `@State`), 화면은 `.undoToast(_:hidden:)`다. 4초(VoiceOver면 8초) 뒤 내려간다.
    - 남은 시간 막대는 뺐다. 막대가 4초 동안 움직이면 XCUITest가 앱이 멈추기를 기다리느라, 토스트가 내려간 뒤에야 "실행 취소"를 누르려 했다(PR #24 첫 CI).
    - 되돌리기는 `ItemSnapshot`으로 한다.
      - 지운 것: 같은 `id`, 만든 시각, 완료 표시로 되살린다.
      - "나중에": 그때의 날짜와 힌트로 돌린다.
      - 복제: 복사본을 지운다.
    - 하루 상세(목록 밀기, 타임라인 메뉴)와 "나중에"(밀어서 삭제)에 띄운다.
    - 시트 안에 띄우므로 시트가 닫히면 함께 사라진다. 달력 칸을 가리지 않는다.
  - 팁
    - `GestureTips.swift`에 `RangePressTip`, `MoveItemTip`, `InboxDropTip`가 있다.
    - 보일 때만 행을 만든다(`shouldDisplayUpdates`). 숨긴 `TipView`가 빈 행이나 여백으로 남아 스크린샷과 칸 위치를 바꾸지 않게 하려는 것이다.
    - 직접 해 보면 `.began`에서 닫는다.
    - 테스트 실행에서는 `Tips.hideAllTipsForTesting()`, `-UITestShowTips`면 `resetDatastore` + `showAllTipsForTesting()`이다.
  - 카테고리 칩
    - `CategoryChips`를 일정 편집과 반복 할일 편집이 같이 쓴다.
    - Form 행 안의 버튼이 함께 눌리지 않게 `.plain`으로 둔다.
    - 반복 할일 편집의 "사용" 토글은 따로 섹션으로 옮겼다.
  - "나중에"
    - items `@Query(animation: .snappy)`
    - 빠른 입력으로 넣으면 입력창에 "넣음"이 1.2초 보이고 light 햅틱이 온다.

### Phase 18 — 일정 편집 화면 정리 (사용자 요청 2026-10-22)
- 달력 일정의 "날짜 지정" 토글은 늘 켜져 있으므로 뺀다.
  - 대신 삭제 바로 위에 "나중에 할일로 미루기"를 둔다. 누르면 시트가 닫히고 "나중에" 탭이 열린다.
  - "나중에" 항목을 고칠 때는 토글을 그대로 둔다. 편집에서 날짜를 정해 달력에 넣는 길이기 때문이다.
- 순서를 제목 → 날짜·시간 → 카테고리 → 본문 → 알림으로 바꾼다.
- 알림을 카테고리처럼 한 줄 칩으로 바꾼다. 카테고리와 달리 여러 개를 켤 수 있다.
- "종일" 토글을 반대 뜻의 "시간 지정"으로 바꾼다. 켜면 시각까지, 끄면 날짜만 고른다. "날짜 정하기" 시트도 같다.
- 새 일정의 기본값
  - 타임라인의 빈 곳: 그 시각부터 "시간 지정"이 켜진 채 연다(예전과 같다).
  - 하루 상세의 +, 달력 머리의 +, 날짜를 꾹 눌렀다 그대로 떼기: "시간 지정"이 꺼진 그 날 하루로 연다.
- 모델과 CloudKit 스키마는 바뀌지 않는다.
- **완료 기준**
  - 앱 단위 테스트가 통과한다.
    - `ItemDraftTests`: `hasTimeIsTheOppositeOfAllDay`, `newItemDraftIsOneDayWithoutTime`, `deferringSavesTheEditsAndKeepsTheShape`
    - `LaunchOptionsTests.toastsStayLongerInUITests`
  - UI 테스트 `EditorTests`(스크린샷 38–39)가 통과한다.
  - 기존 테스트가 "시간 지정"으로 통과한다: `DragTests`(28), `ScreenshotTests.testDayDetailAndEditing`, `testInboxAssignAndDefer`, `TimelineTests`
  - 기기 체크리스트 16장으로 확인한다.
- **구현 메모**
  - 미루기
    - 고친 내용도 함께 저장한다. 초안의 `hasDate`를 끄고 `apply`하면, 지금 모양을 힌트로 남기고 `moveToInbox(order: Item.topInboxOrder(in:))`로 간다.
    - 제목이 비어 있으면 저장 버튼처럼 누를 수 없다.
    - `CalendarTab`이 하루 상세를 닫으면 위의 편집 시트도 함께 닫힌다. 탭은 시트가 다 닫힌 뒤(`sheet(item:onDismiss:)`) 바꾼다. 시트가 떠 있는 채로 탭을 바꾸지 않으려는 것이다.
    - 편집 화면은 열 때 "나중에" 항목이었는지를 `@State`(`isInboxItem`)로 둔다. 모델을 보면 미룬 뒤 닫히는 동안 날짜 토글이 나타났다 사라진다.
    - 되돌리기 토스트는 두지 않는다. 시트가 닫히고 "나중에" 탭 맨 위에 미룬 일정이 보이며, 꾹 눌러 바로 다시 넣을 수 있다.
  - 알림 칩
    - `ReminderChips`(`Features/Common`)다. `CategoryChips`와 같은 크기의 캡슐이고, 켠 칩은 강조 색으로 채운다.
    - 칩을 켜서 비트가 늘 때 `requestAuthorization()`을 부른다(예전 토글과 같다).
    - UI 테스트는 칩을 누르지 않는다. 알림 권한 창이 떠서 화면을 가리기 때문이다. 켜고 끄기는 기기 체크리스트 16-3으로 확인한다.
  - 새 일정
    - `ItemEditorView.Mode.new(day)`가 `ItemDraft.newAllDay(from: day, through: day)`로 연다. 달력 머리의 +, 꾹 눌렀다 떼기, 하루 상세의 +가 모두 이 길이다.
    - 시간 일정으로 여는 길은 타임라인의 빈 곳(`.newTimed`)뿐이다.
  - "날짜 정하기" 시트(`AssignDateSheet`)도 "시간 지정" 토글이다(`hint.isAllDay`의 반대 바인딩).
  - 토스트 시간
    - PR #25 첫 CI(2026-10-22): 빌드는 됐고 92개 중 91개가 통과했다.
      - `MotionTests.testUndoToastBringsBackASwipeDeletedItem`만 "toast.undo"를 누르지 못했다.
      - 기록으로 보면 지운 뒤 스크린샷까지 5초가 걸려, 4초짜리 토스트가 먼저 내려갔다. main의 직전 두 번은 통과했다.
    - UI 테스트(`-UITestSeedData`)에서는 토스트를 20초 둔다(`LaunchOptions.keepsToastsLonger` → `UndoToastState.usesUITestDuration`). 앱에서는 그대로 4초(VoiceOver면 8초)다.

### Phase 19 — 하루 상세에서 옮길 때 시트 닫기, 맨 위 X로 취소 (사용자 요청 2026-10-23)
- 하루 상세에서 일정이나 할일을 꾹 눌러 옮기기가 되면 시트를 닫아 달력 전체가 보이게 한다. 예전에는 64pt로 작아진 시트가 아래에 남았다.
- 화면 맨 위 가운데에 X를 띄운다. 거기서 놓으면 옮기지 않는다.
- 필요한 곳에 움직임을 넣는다.
- 모델과 CloudKit 스키마는 바뀌지 않는다.
- **완료 기준**
  - 앱 단위 테스트 `ItemMoveSessionTests`(X의 자리와 놓는 범위)가 통과한다.
  - UI 테스트가 통과한다.
    - `DragTests.testDroppingOnTheCancelMarkKeepsTheItemAndBringsTheSheetBack`(스크린샷 40): X에 놓으면 일정이 그대로이고, 시트가 다시 보이며 행을 누를 수 있다.
    - 기존 `DragTests.testLongPressMovesAnItemFromTheDayDetailToAnotherDay`(33)
  - 기기 체크리스트 17장으로 확인한다.
- **설계와 다른 점:** 취소하면 하루 상세가 원래 높이로 다시 열린다(예전 동작과 같다). 옮기기만 그만두고 그 날의 목록으로 돌아가는 것으로 해석했다.
- **구현 메모**
  - 시트는 정말 닫지 않고 감춘다(`DayDetailView`의 `SheetCard`).
    - 닫으면 꾹 누른 행이 창에서 빠져 손가락 추적이 끊긴다. Phase 11 "나중에" 끌기가 탭을 바꾸다 놓이지 않던 것과 같은 원인이다.
    - 시트는 예전처럼 `movingDetent`(64pt)로 내린다. large에서 뒤로 물러났던 달력이 제 크기로 돌아온다.
    - 동시에 카드(띄우기 컨테이너 바로 아래 뷰, 배경과 그림자 포함)의 투명도를 0으로 한다. 내려가며 사라지므로 닫히는 것처럼 보인다.
      - 카드는 누른 곳의 뷰(`window.hitTest`)에서 응답 사슬로 띄운 화면을 찾아 구한다.
      - 투명해도 누르던 손가락은 행의 `WindowPressGesture`가 끝까지 받는다.
      - 어두운 막은 예전처럼 `presentationBackgroundInteraction(.enabled)`으로 끈다.
    - 다른 날에 놓으면 감춘 채로 `dismiss()`한다. 취소하면 원래 높이로 올리며 0.3초 동안 다시 보인다.
    - 작아진 시트 위의 안내 줄(`MoveHintBar`)은 뺐다. 놓을 곳 안내는 손가락 위의 미리보기가 한다.
  - X(`MoveCancelMark`)
    - `ItemMoveSession.begin(…, showsCancelMark: true)`가 창에 붙인다. 미리보기보다 위에 붙여서, 미리보기가 맨 위로 올라와도 가리지 않는다.
    - 가운데는 화면 가운데, 안전 영역 위 끝에서 26pt 아래다(`cancelMarkCenter`). 달력 머리 줄의 연·월과 버튼 사이 빈자리다.
    - 놓는 자리(`cancelZone`)는 가로 120pt이고, 화면 맨 위 끝부터 X 아래 36pt까지다. 달력 칸에 걸치지 않는다.
    - "나중에" → 달력 넣기에는 두지 않는다(요청 범위 밖). 덮개 달력 밖에서 떼면 예전처럼 취소다.
  - 움직임
    - 시작: 미리보기가 들어 올려지고(예전과 같다), 시트가 내려가며 0.2초 동안 사라진다. X는 0.08초 뒤 0.5배에서 spring으로 튀어나온다.
    - X 위: X가 1.2배로 커지며 채워진다(`.snappy`). 미리보기는 0.85배, 투명도 0.55가 되고 "놓으면 옮기지 않습니다"로 바뀐다. 들어가고 나올 때 선택 햅틱이 온다.
      - 미리보기 크기를 transform으로 바꾸므로, 손가락을 따라갈 때 `frame` 대신 `center`로 옮긴다.
    - X에서 놓기: 미리보기가 시작한 자리로 돌아가며 사라지고, X는 줄어들며 사라지고, 시트가 올라오며 나타난다.
    - 다른 날에 놓기: 예전처럼 미리보기가 그 칸으로 빨려 들고, 놓은 날이 빛나며 막대가 튀어 들어온다. X는 줄어들며 사라진다.
    - 동작 줄이기면 X와 미리보기는 크기를 바꾸지 않고 투명도만 바꾼다. 시트는 투명도만 바꾸므로 그대로다.

### Phase 20 — 반복 탭 요약 기간 (사용자 요청 2026-10-27)
- 반복 탭 오른쪽 요약이 규칙과 상관없이 "이번 달 완료/오늘까지 시작한 주기"였다. 최근에 만든 매일·매주 할일은 "이번 달 1/1"로 보여, 체크 표시와 같은 말만 했다.
- 요약 기간을 규칙에 맞춘다(사용자 결정). 주기가 여러 번 들어가는 가장 짧은 기간이다.
  - 매일, 요일 여럿인 매주: 이번 주(설정의 주 시작 요일부터 7일)
  - 요일 하나인 매주: 이번 달
  - 매월(n일, 말일): 올해
- 분모는 그 기간에 시작하는 주기 전체다. 아직 오지 않은 주기도 센다. 그래서 링이 기간 동안 차오르고, 기간 첫날에도 "1/1"이 되지 않는다.
  - 시작일 전과 종료일 뒤의 주기는 세지 않는다. 그 기간에 주기가 없으면 요약을 숨긴다(예전과 같다).
- 모델과 CloudKit 스키마는 바뀌지 않는다.
- **완료 기준**
  - Core 테스트 `RecurrenceEngineTests`(요약 기간, 기간 범위, 매일·매주·매월 요약, 주기가 없는 기간)가 통과한다.
  - UI 테스트 `FeatureScreenshotTests.testRecurringTasks`(스크린샷 23)가 통과한다.
    - 10/19(월) 샘플: 물 2L 마시기 "이번 주 1/7", 헬스장 "이번 주 0/3", 관리비 납부 "올해 1/4"
    - 체크하면 "이번 주 2/7", 취소하면 "이번 주 1/7"
  - 기기 체크리스트 18장으로 확인한다.
- **구현 메모**
  - Core `RecurrenceRule.summaryPeriod` → `RecurrenceSummaryPeriod`(`range(containing:firstWeekday:)`, `koreanText`)
  - Core `Recurrence.summary(on:firstWeekday:completedCycleStarts:)` → `RecurrenceSummary`(`done`, `total`, `fraction`, `koreanText`). 예전 `monthSummary`를 대신한다.
  - `RecurringTaskRow`는 `@AppStorage(AppSettings.firstWeekdayKey)`로 주 시작 요일을 읽는다.
  - 기간은 오늘이 속한 달력 기간이다. 지난 기간에 시작한 주기(예: 일요일 시작 주에서 금–일 주기)를 이번 주에 체크하면, 상세 문구는 바뀌지만 요약은 그 주기가 시작한 기간에 센다.

### Phase 21 — App Store 등록 준비 (사용자 요청 2026-11-01)
- App Store Connect에 넣을 문구, 지원·개인정보 처리방침 페이지, 스크린샷과 미리보기 영상을 만든다. 넣는 순서와 답은 `docs/APP_STORE.md`에 있다.
- 문구: `appstore/metadata/ko/*.txt`(fastlane deliver와 같은 파일 이름), 심사 메모 `review_information/notes.txt`
  - 길이와 키워드 형식은 `scripts/appstore/check_metadata.py`가 확인한다. URL은 앱의 `AppLinks`와 같아야 한다.
- 안내 페이지: `site/`(소개, 지원, 개인정보 처리방침) → Pages 워크플로(main) → `https://swpark3179.github.io/DayGrid/`
  - 처음 한 번 사용자가 Settings → Pages의 Source를 GitHub Actions로 바꾼다.
  - 문의 창구는 GitHub 이슈다. 이메일은 사용자가 정하면 지원 페이지에 더한다.
- 앱
  - 설정 → 정보에 "지원 및 문의", "개인정보 처리방침" 링크(심사 지침 5.1.1: 앱 안에서도 개인정보 처리방침을 열 수 있어야 한다)
  - 개인정보 매니페스트 `DayGrid/PrivacyInfo.xcprivacy`: 추적 없음, 수집 데이터 없음, UserDefaults 이유 CA92.1
  - `MARKETING_VERSION`을 1.0으로 올렸다. ASC의 첫 버전(1.0)과 같아야 빌드를 고를 수 있다.
- 스크린샷과 영상: "App Store assets" 워크플로(`appstore-assets.yml`)
  - capture(macOS): 6.9형 시뮬레이터에서 `AppStoreScreenshotTests`(01–09)와 `AppStorePreviewTests`(영상 2개)
    - 보통 CI에서는 건너뛴다. 워크플로가 `TEST_RUNNER_DAYGRID_APPSTORE=1`로 켠다.
    - 영상은 `scripts/appstore/record_previews.py`가 `simctl io recordVideo`로 녹화한다. 테스트와는 Mac의 폴더(`~/Library/Caches/daygrid-appstore`)에 파일을 만들어 신호를 주고받는다.
  - compose(Linux): `compose_screenshots.py`가 문구와 기기 틀을 입혀 1320×2868(6.9형)과 1206×2622(6.3형)로 만든다. `encode_previews.py`가 영상을 886×1920, 30fps, 15–30초, 무음 스테레오로 맞춘다.
  - 결과는 `app-store-assets` 아티팩트다. 문구는 `appstore/screenshots.json`에서 고친다.
- iCloud 동작(사용자 질문): 앱 안 로그인 없이 기기의 Apple 계정 iCloud 개인 DB에 저장한다. `docs/ICLOUD.md` "동작 방식"
  - 2026-11-01 CloudKit schema check(실행 #6): Production에 레코드 타입 7개와 필드가 모두 있다.
- **완료 기준**
  - "App Store assets" 워크플로가 스크린샷 9장(두 크기)과 영상 2개를 만든다.
  - 앱 단위 테스트 `PrivacyManifestTests`, UI 테스트 `FeatureScreenshotTests.testSettingsSyncStatus`(설정의 링크)가 통과한다.
  - 기기 체크리스트 19장으로 확인한다.

### 이후 확장 (선택)
- 오늘/월간 위젯, App Intents(Siri, 단축어)로 빠른 할일 추가
- 검색, JSON 내보내기·가져오기(백업), 앱 아이콘 다듬기
- 반복 "일정"(할일이 아닌 정기 일정)

## 검증 방법
- **Core 로직:** `swift test --package-path Packages/DayGridCore`를 로컬 Linux 툴체인 또는 CI ubuntu 잡에서 실행한다. 날짜 규칙은 모두 여기서 테스트로 고정한다.
- **앱:** CI macOS 잡에서 `xcodegen generate && xcodebuild test -scheme DayGrid -destination 'platform=iOS Simulator,name=<고정 기기>'`를 실행한다.
  - 앱 단위 테스트: in-memory SwiftData
  - UI 테스트: 고정 날짜와 샘플 데이터로 단계별 핵심 화면 스크린샷을 아티팩트로 남긴다.
- **실기기:** Phase 3 이후 단계마다 TestFlight 빌드를 올리고, PR에 적은 수동 체크리스트로 확인한다. 알림, 연락처 권한, iCloud처럼 시뮬레이터로 검증하기 어려운 부분이 대상이다.

## 주요 리스크와 대응
- **SwiftUI 미리보기를 쓸 수 없다(Mac 없음).** 화면 하나를 고칠 때마다 CI를 거쳐 약 10분이 걸린다. UI 테스트 한 번에 여러 상태의 스크린샷을 몰아서 찍어 왕복 횟수를 줄인다.
- **음력 변환 정확도:** 연도별 검증 테스트를 두고, 윤달 규칙을 명시한다.
- **대기 알림 64개 제한:** 30일 윈도우 안에서 다시 스케줄링한다.
- **CloudKit 스키마 제약:** Phase 1부터 모델 규칙을 지킨다. 프로덕션 스키마를 배포한 뒤에는 필드 추가만 한다.


## 나중에 할 테스트
사용자 결정(2026-10-19): CI 결과를 기다리지 않고 다음 단계를 진행한다. 빌드 오류는 바로 고치고, 아래 항목은 나중에 몰아서 확인한다.

- [x] PR #7(Phase 4) CI 다시 확인: 테스트를 고친 뒤(101dc99) 모두 통과했다.
  - 편집 화면의 삭제 버튼이 화면 밖에 있었다.
  - 오른쪽 끝까지 끌면 "나중에"가 전체 밀기로 바로 실행됐다.
- [x] Phase 5–7 UI 테스트(`DayGridUITests/FeatureScreenshotTests.swift`, 스크린샷 16–24)
  - Phase 5: 본문 미리보기(표, HTML, 체크리스트), 다크 모드, 서식 툴바와 굵게 삽입
  - Phase 6
    - 달력 날짜 칸: 개천절, 대체공휴일, 한글날, 회사 창립기념일, 생일, 반복 할일 완료
    - 생일 배너 → 생일 목록, 하루 상세의 기념일 섹션
    - 개인 휴일 목록, 생일 편집 화면
  - Phase 7: 반복 탭(이번 달 요약, 체크와 취소), 하루 상세에서 체크와 취소, 편집 화면(매주 요일), 새 반복 할일 저장
- [x] Phase 6–8 앱 단위 테스트
  - `RecurringTaskTests`: 규칙 저장, 같은 주기 중복 체크 방지, 주기 상태, 사용 중 조회, 완료 기록 함께 삭제
  - `BirthdayAndHolidayModelTests`: 생일 저장, n번째 생일, 개인 휴일 기간과 조회
  - `ItemDraftTests`, `ItemStoreTests`: 알림 선택 왕복과 복제, 샘플 데이터 개수
- [x] TestFlight 기기 확인: `docs/DEVICE_CHECKLIST.md` 1–6장을 2026-10-19에 사용자가 모두 확인했다.
  - Phase 4: 빠른 입력, 밀기 동작, 순서 바꾸기, 홈 화면 퀵 액션, 기존 데이터
  - Phase 5: 키보드 툴바, 실행 취소, 링크 열기, 다크 모드
  - Phase 6: 연락처 가져오기(권한, 일부 허용, 음력, 다시 가져오기), 공휴일 보정 파일 원격 갱신
  - Phase 8: 권한 요청 시점, 종류별 알림, "완료" 동작, 알림을 눌러 이동, 백그라운드 새로 고침
- [ ] Phase 10 "반복" 탭 배지: UI 테스트로는 확인할 수 없다. 기기 체크리스트 8-4로 확인한다.
  - iOS 26 탭 막대는 배지 숫자를 접근성 라벨·값에 넣지 않는다. PR #14 CI에서 라벨 "반복", 값이 비어 있었다.
  - 개수 계산은 `RecurringTaskTests.sampleDataHasTwoDueTasksToday`가 확인한다.
- [x] Phase 11 "나중에" → 달력 놓기: UI 테스트(`DragTests.testDraggingAnInboxItemOntoTheCalendar`)의 마지막 확인을 기대 실패(strict 아님)로 두었다. 기기 체크리스트 9-5–9-7로 확인한다.
  - 2026-10-21 기기에서도 놓기가 들어가지 않았다(사용자 확인). Phase 15에서 탭을 바꾸지 않는 방식으로 다시 만들었다.
  - PR #15 CI에서 끌기를 시작하자 달력 탭으로 바뀌었다. 그러나 놓은 뒤 항목이 어느 날에도 없었다.
  - 원인 후보
    - XCUITest의 끌기가 시스템 끌어 놓기로 이어지지 않음
    - 탭이 바뀌면서 끌기를 시작한 목록이 화면에서 빠져 끌기가 끝남
  - 기기에서도 안 되면 두 번째가 원인이다. 그때는 탭을 바꾸는 방식을 고친다.
- [ ] Phase 13 하루 상세 타임라인: PR CI 확인
  - Core: `DayTimelineTests`, `DayAgendaTests.timelineTakesEverythingWithATime`
  - UI: `TimelineTests`(스크린샷 30–32)
    - 시트를 large로 올리는 막대 끌기
    - 오른쪽 빈 곳 좌표 누르기
    - 새 블록이 병원 옆 열에 놓이는지
  - 기기 확인은 기기 체크리스트 11장으로 한다.

- [ ] Phase 14 달력 막대, 하루 상세에서 옮기기, 동기화 진단: PR CI 확인
  - Core: `MonthLayoutTests`(막대·칩), `CloudKitErrorReaderTests`(앱 기록), `CloudSyncStateTests`(`attachLog`)
  - 앱: `ItemStoreTests.movingKeepsTheShapeOfTheSchedule`
  - UI: `DragTests.testLongPressMovesAnItemFromTheDayDetailToAnotherDay`(스크린샷 33), `TimelineTests`의 본문 버튼 크기
  - 기기
    - 체크리스트 12장
    - 앱 기록 읽기(OSLogStore)가 실제로 CloudKit 오류 줄을 찾는지는 Production 배포 전 빌드에서만 볼 수 있다. 체크리스트 7-2로 확인한다.
      - 2026-10-21에 확인했다. `invalidArguments(12): Cannot create new type CD_PersonalHoliday in production schema`를 찾았다(사용자 확인).

- [ ] Phase 15 "나중에" 키보드, 꾹 눌러 달력에 넣기: PR CI 확인
  - 앱: `CalendarDropStateTests`(창 좌표 → 날짜, 숨긴·빠진 페이지, 가장자리 넘기기)
  - UI
    - `DragTests.testDraggingAnInboxItemOntoTheCalendar`(스크린샷 29): 덮개 달력의 10/14에 넣으면 달력 탭으로 바뀌고 그 날에 보인다.
    - `ScreenshotTests.testQuickAddShortcut`: 입력창 안을 누르면 포커스가 그대로이고, 제목 줄을 누르면 포커스가 풀린다.
  - 기기: 체크리스트 13장

- [ ] Phase 16 테마 설정, 달력 탭에서 반복 할일 빼기: PR CI 확인
  - Core: `KoreanCalendarTests`(DayMarks에서 반복 할일 완료를 뺌)
  - 앱: `AppSettingsTests`(테마 값, `NotificationRouter.open`), `LaunchOptionsTests`
  - UI
    - `ScreenshotTests.testCalendarDarkMode`(03, 34): `-appearance dark`로 달력이 어둡고, 설정의 테마가 "다크"로 보인다.
    - `FeatureScreenshotTests.testBodyPreviewDarkMode`(18)
    - `testHolidaysAndBirthdays`: 10/12 칸에 반복 할일 완료가 없다.
    - `testRecurringTasks`: 10/19 하루 상세에 반복 할일이 없다.
  - 기기: 체크리스트 14장

- [ ] Phase 17 UI·모션 개선: PR CI 확인
  - Core: `LocalDateKoreanTests.koreanRangeText`
  - 앱
    - `ItemStoreTests.aDeletedItemComesBackFromItsSnapshot`, `undoingMoveToInboxPutsTheScheduleBack`
    - `CalendarDropStateTests.aDayCellHasAWindowFrame`, `landingReplacesTheEarlierLanding`
    - `LaunchOptionsTests.tipsAreHiddenInTestRunsUnlessAsked`
  - UI
    - `MotionTests`: 팁(35), 되돌리기 토스트(36), 카테고리 칩(37)
      - PR #24 첫 CI(2026-10-22): 빌드는 됐고 88개 중 87개가 통과했다. `testUndoToastBringsBackASwipeDeletedItem`만 "toast.undo"를 누르지 못했다. 토스트의 4초짜리 남은 시간 막대 애니메이션 때문이었다. 막대를 빼고 다시 확인한다.
    - 기존 테스트가 그대로 통과하는지 본다: 밀기 삭제·나중에, 끌기(28, 29, 33), 반복 체크, 편집 화면
  - 기기: 체크리스트 15장

- [ ] Phase 18 일정 편집 화면 정리: PR CI 확인
  - 앱: `ItemDraftTests`(시간 지정, 하루 상세 +, 미루기)
  - UI
    - `EditorTests`: 편집 배치와 알림 칩(38), 미룬 뒤 "나중에" 탭(39)
      - 하루 상세와 편집 시트가 함께 닫히고 "나중에" 탭이 열리는지 본다. 안 되면 탭을 바꾸는 시점(`onDismiss`)부터 의심한다.
    - `EditorTests.testNewItemsFromTheCalendarStartWithoutTime`: 달력 머리의 +, 꾹 눌렀다 떼기
    - "시간 지정"으로 바꾼 확인: `DragTests`(28), `ScreenshotTests.testDayDetailAndEditing`(09는 이제 종일로 열린 화면), `testInboxAssignAndDefer`(날짜 정하기), `TimelineTests`
    - `MotionTests.testUndoToastBringsBackASwipeDeletedItem`: UI 테스트에서 토스트를 20초 둔 뒤 통과하는지 본다.
  - 기기: 체크리스트 16장

- [ ] Phase 19 하루 상세에서 옮길 때 시트 닫기, 맨 위 X로 취소: PR CI 확인
  - 앱: `ItemMoveSessionTests`(X의 자리와 놓는 범위)
  - UI
    - `DragTests.testDroppingOnTheCancelMarkKeepsTheItemAndBringsTheSheetBack`(스크린샷 40)
      - 실패하면 놓은 자리가 `cancelZone` 안인지(시뮬레이터의 안전 영역 높이, 머리 줄 높이)부터 본다.
      - 시트가 보이는데 행을 누를 수 없으면 카드의 투명도가 돌아오지 않은 것이다.
    - `DragTests.testLongPressMovesAnItemFromTheDayDetailToAnotherDay`(33): 감춘 시트로도 끌기와 닫기가 그대로인지 본다.
  - 기기: 체크리스트 17장. 시트가 정말 사라지는지(카드를 못 찾으면 예전처럼 64pt 시트가 남는다)와 움직임은 기기에서만 볼 수 있다.

- [ ] Phase 20 반복 탭 요약 기간: PR CI 확인
  - Core: `RecurrenceEngineTests`(`summaryPeriodFollowsTheRule`, `summaryPeriodRanges`, `dailySummaryCountsTheWholeWeek`, `weeklySummaryUsesTheWeekOrTheMonth`, `monthlySummaryUsesTheYear`, `noSummaryWithoutCyclesInThePeriod`)
  - UI: `FeatureScreenshotTests.testRecurringTasks`(스크린샷 23)
  - 기기: 체크리스트 18장

- [ ] Phase 21 App Store 등록 준비: PR CI 확인
  - 앱: `PrivacyManifestTests`(번들에 `PrivacyInfo.xcprivacy`가 들어갔는지)
  - UI: `FeatureScreenshotTests.testSettingsSyncStatus`(설정의 지원·개인정보 처리방침 링크)
  - "App Store assets" 워크플로
    - `TEST_RUNNER_DAYGRID_APPSTORE`가 테스트 실행기에 넘어가는지(넘어가지 않으면 모두 건너뛰어 "App Store 화면이 하나도 없다"로 실패한다)
    - 시뮬레이터 안의 테스트가 Mac 폴더에 신호 파일을 쓰고 읽는지(영상 녹화)
    - 타임라인(03)은 시트를 크게 올린 화면인지
  - 기기: 체크리스트 19장

## 진행 방식과 현황
- 단계마다 브랜치 1개, PR 1개로 진행한다. CI green과 스크린샷 확인을 마친 뒤 머지한다.
- 단계를 시작할 때 이 문서의 해당 Phase를 다시 읽고, 끝나면 아래 체크박스를 갱신한다.

- [x] Phase 0: 기반과 CI
- [x] Phase 1: 데이터 모델과 달력 첫 화면
- [x] Phase 2: 날짜 상세와 일정 편집
- [x] Phase 3: TestFlight 배포 파이프라인
- [x] Phase 4: 나중에 할일(인박스), 배정과 보류
- [x] Phase 5: 상세 본문 (마크다운 + HTML)
- [x] Phase 6: 공휴일, 개인 휴일, 생일
- [x] Phase 7: 반복 할일
- [x] Phase 8: 알림 (미리알림)
- [ ] Phase 9: iCloud 동기화(TestFlight 서명 문제로 기기 확인 전)
- [ ] Phase 10: 달력·본문 개선(연·월 이동, 개인 휴일 색, 반복 배지, 본문 읽기 화면)
- [ ] Phase 11: 끌어서 일정 넣기(꾹 눌러 기간, 나중에 → 달력)
- [ ] Phase 12: 잠금화면 위젯(남은 반복 할일)
- [ ] Phase 13: 하루 상세 타임라인(보기 방식 설정, 업무 시간, 빈 곳 눌러 새 일정)
- [ ] Phase 14: 달력 막대(하루짜리 시간 일정), 하루 상세에서 꾹 눌러 옮기기, 타임라인 본문 버튼, 동기화 진단(앱 기록)
- [ ] Phase 15: "나중에" 키보드 내리기, 꾹 눌러 덮개 달력에 넣기(탭을 바꾸지 않음)
- [ ] Phase 16: 테마 설정(시스템/라이트/다크), 달력 탭에서 반복 할일 빼기
- [ ] Phase 17: UI·모션 개선(충전 링, 기간 띠, 착지 펄스, 되돌리기 토스트, 끌기 미리보기, 체크 피드백, 팁, 제목 숫자 전환, 카테고리 칩, 빠른 입력)
- [ ] Phase 18: 일정 편집 화면 정리(날짜 토글 대신 "나중에 할일로 미루기", 카테고리 → 본문 → 알림, 알림 칩, "시간 지정", 새 일정은 시간 없이)
- [ ] Phase 19: 하루 상세에서 꾹 눌러 옮길 때 시트 닫기, 맨 위 가운데 X로 취소, 움직임
- [ ] Phase 20: 반복 탭 요약 기간(매일·매주는 이번 주, 요일 하나인 매주는 이번 달, 매월은 올해)
- [ ] Phase 21: App Store 등록 준비(문구, 지원·개인정보 처리방침 페이지, 스크린샷·미리보기 워크플로, 개인정보 매니페스트, 버전 1.0)
