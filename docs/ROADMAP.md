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
- 체크하면 `completedDay`(체크한 날)에 완료 표시가 나타난다. 월 화면에는 "이번 달 3/4 완료" 요약을 보여준다.
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
  - CloudKit 같은 entitlement가 생기면(Phase 9) 서명 없는 아카이브로는 부족할 수 있다. 그때 개발 인증서 `.p12` Secret 방식으로 바꾼다.
- **완료 기준:** iPhone의 TestFlight 앱에서 설치하고 실행된다. 이후 단계는 기기에서도 확인한다.
- **결과(2026-10-19):** 첫 실행(빌드 1)에서 클라우드 서명과 업로드가 그대로 성공했다(사용자 확인). `.p12` 대안은 쓰지 않았다.

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

### Phase 7 — 반복 할일
- `RecurringTask`와 `RecurrenceCompletion` 모델, 그리고 `RecurrenceEngine`을 만든다. `RecurrenceEngine`은 발생일, 현재 활성 주기, 주기별 상태(완료/진행 중/놓침)를 계산한다.
- "반복" 탭에서 규칙을 만들고 편집한다. 매일, 매주(요일 여러 개), 매월(n일 또는 말일)을 지원한다.
- 오늘 날짜 상세에는 활성 주기 체크박스와 "n일째" 배지를 보여준다. 달력의 완료한 날에는 ✓를 찍고, 월 요약을 보여준다. 체크는 취소할 수 있다.
- **완료 기준:** 위 "반복 할일 규칙"의 경계 사례 단위 테스트가 통과한다. 경계 사례는 말일 보정, 주기가 넘어갈 때의 놓침 판정, 같은 주기 안의 중복 체크 방지다.

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

### Phase 9 — iCloud 동기화
- CloudKit 컨테이너 entitlement와 원격 알림 Background Mode를 추가하고, `ModelConfiguration(cloudKitDatabase: .private(...))`로 설정한다.
- 시드 카테고리 중복을 제거하는 병합 처리를 넣고, 동기화 상태를 설정 화면에 표시한다.
- **완료 기준:** 앱을 지웠다가 다시 설치해도 데이터가 복원된다. 기기가 2대면 양방향 반영도 확인한다.

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

- [ ] PR #7(Phase 4) CI의 UI 테스트 결과 확인과 수정(`testInboxAssignAndDefer`, `testQuickAddShortcut`)
- [ ] Phase 4 TestFlight 기기 확인
  - 빠른 입력을 연속으로 쓸 수 있는지
  - 밀기 동작(삭제, 날짜, 완료, 나중에)
  - 끌어서 순서 바꾸기
  - 홈 화면 퀵 액션
  - 기존 데이터가 그대로 남는지
- [ ] Phase 5 UI 테스트
  - 본문 미리보기 스크린샷: 표, HTML, 체크리스트, 다크 모드(샘플 "출장"의 본문)
  - 서식 툴바 스크린샷
- [ ] Phase 5 TestFlight 기기 확인: 키보드 툴바, 실행 취소, 링크 열기, 다크 모드

## 진행 방식과 현황
- 단계마다 브랜치 1개, PR 1개로 진행한다. CI green과 스크린샷 확인을 마친 뒤 머지한다.
- 단계를 시작할 때 이 문서의 해당 Phase를 다시 읽고, 끝나면 아래 체크박스를 갱신한다.

- [x] Phase 0: 기반과 CI
- [x] Phase 1: 데이터 모델과 달력 첫 화면
- [x] Phase 2: 날짜 상세와 일정 편집
- [x] Phase 3: TestFlight 배포 파이프라인
- [x] Phase 4: 나중에 할일(인박스), 배정과 보류
- [ ] Phase 5: 상세 본문 (마크다운 + HTML)
- [ ] Phase 6: 공휴일, 개인 휴일, 생일
- [ ] Phase 7: 반복 할일
- [ ] Phase 8: 알림 (미리알림)
- [ ] Phase 9: iCloud 동기화
