# App Store 등록 준비

App Store Connect(ASC)에 넣을 내용과 순서다. 문구는 `appstore/metadata/`에, 스크린샷과 미리보기 영상은 "App Store assets" 워크플로의 아티팩트에 있다.

## 한눈에 보기
| ASC 항목 | 넣을 값 | 파일 |
|---|---|---|
| 이름 | DayGrid | `appstore/metadata/ko/name.txt` |
| 부제(30자) | 달력으로 보는 일정·할일 플래너 | `ko/subtitle.txt` |
| 프로모션 텍스트(170자) | 앱을 열면 바로 한 달이 보여요… | `ko/promotional_text.txt` |
| 설명(4000자) | ■ 한 달이 한눈에 보이는 달력… | `ko/description.txt` |
| 키워드(100자) | 캘린더,스케줄,일정관리,… | `ko/keywords.txt` |
| 지원 URL | https://swpark3179.github.io/DayGrid/support/ | `ko/support_url.txt` |
| 마케팅 URL(선택) | https://swpark3179.github.io/DayGrid/ | `ko/marketing_url.txt` |
| 개인정보 처리방침 URL | https://swpark3179.github.io/DayGrid/privacy/ | `ko/privacy_url.txt` |
| 저작권 | 2026 swpark3179(실명으로 바꿔도 된다) | `copyright.txt` |
| 카테고리 | 기본 생산성, 보조 라이프스타일 | `primary_category.txt`, `secondary_category.txt` |
| 심사 메모(4000바이트) | 영어 안내(2.1 정보 요청 6항목: 녹화, 목적, 사용법, 외부 서비스, 지역, 규제) | `review_information/notes.txt` |
| 심사 첨부 파일 | 실기기 화면 녹화(6번) | 저장소에 두지 않는다 |
| 스크린샷 | 6.9형 1320×2868, 6.3형 1206×2622 각 9장 | 아티팩트 `screenshots/framed/` |
| 앱 미리보기 | 886×1920, 15–30초, 2개 | 아티팩트 `previews/` |

- 문구 길이와 키워드 형식은 `python3 scripts/appstore/check_metadata.py`로 확인한다. 워크플로도 같은 검사를 한다.
- 문구를 고치면 이 파일들을 고친 뒤 ASC에 다시 붙여 넣는다. ASC와 자동으로 맞추지는 않는다.

## 1. 머지한 뒤 한 번 할 일
1. **GitHub Pages 켜기**
   - 저장소 **Settings → Pages → Build and deployment → Source**를 **GitHub Actions**로 바꾼다.
   - **Actions → Pages → Run workflow**(main)를 실행한다. 다음부터는 `site/`를 바꿔 머지하면 저절로 올라간다.
   - 위 세 URL이 열리는지 본다. 지원 URL과 개인정보 처리방침 URL은 심사 전에 열려야 한다.
2. **CloudKit Production 스키마**
   - 2026-11-01 "CloudKit schema"(check, 실행 #6)에서 Production에 레코드 타입 7개와 필드가 모두 있었다. 지금 모델 그대로면 할 일이 없다.
   - App Store 버전도 TestFlight와 같은 Production 환경을 쓴다. 모델을 바꾸면 `docs/ICLOUD.md` 4번(import → Deploy)을 먼저 한다.
3. **새 TestFlight 빌드**
   - 이번 변경으로 앱 버전이 1.0이 되고(`project.yml`의 `MARKETING_VERSION`), 개인정보 매니페스트(`PrivacyInfo.xcprivacy`)와 설정의 지원·개인정보 처리방침 링크가 들어갔다.
   - **Actions → TestFlight → Run workflow**(main)로 올린다. ASC의 버전(처음 만들 때 1.0)과 빌드 버전이 같아야 그 버전에 빌드를 고를 수 있다.
4. **스크린샷과 미리보기 받기**
   - **Actions → App Store assets**의 가장 최근 성공한 실행에서 `app-store-assets` 아티팩트를 내려받는다. 없으면 **Run workflow**로 만든다(30분쯤 걸린다).

## 2. App Store Connect에 넣기
ASC → 앱 → DayGrid.

### 앱 정보
- 이름, 부제: 위 표
- 카테고리: 기본 **생산성**, 보조 **라이프스타일**(보조는 비워도 된다)
- 콘텐츠 권한: "제3자 콘텐츠를 포함하거나 표시하거나 접근합니까?" → **아니요**
  - 공휴일은 앱이 계산하고, 내려받는 보정 파일도 이 저장소의 공개 파일이다.
- 연령 등급: 아래 "연령 등급 답"대로 하면 **4+**가 된다.

### 가격 및 사용 가능 여부
- 가격: 무료(원하는 대로)
- 국가: 화면과 공휴일이 한국어·한국 기준이라 **대한민국**만 골라도 된다.
  - 모든 국가로 내면 중국 본토는 ICP 등록 번호가 필요하므로 뺀다.
  - EU 국가를 고르면 디지털 서비스법(DSA) "판매자 여부"를 먼저 정해야 한다. 개인이 무료로 내면 보통 "판매자 아님"이다.

### 앱 개인정보(App Privacy)
- 개인정보 처리방침 URL: 위 표
- "이 앱에서 데이터를 수집합니까?" → **아니요, 이 앱에서 데이터를 수집하지 않습니다**
  - Apple의 "수집"은 개발자나 제3자가 기기 밖으로 보낸 데이터를 볼 수 있는 경우다.
  - DayGrid의 데이터는 기기와 사용자 본인의 iCloud 개인 DB(CloudKit)에만 있고, 개발자는 볼 수 없다. 연락처의 생일도 기기 안에서 읽어 같은 곳에 저장한다.
  - 광고, 분석, 추적, 제3자 SDK가 없다. `PrivacyInfo.xcprivacy`도 같은 내용이다(추적 없음, 수집 데이터 없음).

### 버전 1.0 페이지
- **앱 미리보기 및 스크린샷**: iPhone 칸마다 맞는 폴더를 끌어 놓는다. 한 칸에 10장까지, 순서는 파일 이름 순서다.
  - 6.9형(iPhone with Dynamic Island, large): `screenshots/framed/iphone-6.9/`
  - 6.3형(iPhone with Dynamic Island, medium, 제출에 꼭 필요한 칸): `screenshots/framed/iphone-6.3/`
  - 나머지 크기는 ASC가 위 크기를 줄여 쓴다.
  - 문구 없이 앱 화면만 쓰고 싶으면 `screenshots/plain/`을 쓴다.
  - 미리보기 영상(`previews/preview-1-calendar.mp4`, `preview-2-tasks.mp4`)은 6.9형 칸에 넣는다. 처리에 몇 시간 걸릴 수 있고, 포스터 프레임(첫 화면)은 ASC에서 고른다.
- 프로모션 텍스트, 설명, 키워드, 지원 URL, 마케팅 URL: 위 표의 파일 내용을 그대로 붙인다.
- **빌드**: 1.0 TestFlight 빌드를 고른다.
- 저작권: `copyright.txt`
- **App Review에 관한 정보**
  - 로그인 필요: **끔**(계정이 없다)
  - 연락처(이름, 전화번호, 이메일): 직접 넣는다. 저장소에는 두지 않는다.
  - 메모: `review_information/notes.txt`. `[[iPhone model]]`, `[[iOS version]]`은 녹화한 기기의 값으로 바꿔 붙인다.
  - 첨부 파일: 실기기 화면 녹화(6번)
- 버전 출시: 승인 후 자동 또는 수동 중 고른다.

수출 규정 질문은 나오지 않는다. `ITSAppUsesNonExemptEncryption = NO`가 빌드에 들어 있다.

### 연령 등급 답
모든 질문에 **없음**/**아니요**로 답한다.
- 앱 안의 기능: 자녀 보호 기능 없음, 나이 확인 없음
- 기능: 제한 없는 웹 접근 아니요(링크는 Safari로 연다), 사용자 생성 콘텐츠 공유 아니요(메모는 본인만 본다), 메시지·채팅 아니요, 광고 아니요
- 성숙한 주제, 의료·건강, 성적 내용, 폭력, 도박, 경품, 무작위 아이템: 모두 없음

## 3. iCloud 동기화는 어떻게 동작하나
`docs/ICLOUD.md`의 "동작 방식"에 정리했다. 요약:
- 앱 안에서 로그인하지 않는다. iPhone **설정 → [이름]**에 로그인한 Apple 계정의 iCloud를 그대로 쓴다.
- 데이터는 그 사용자의 iCloud **개인 데이터베이스**(CloudKit, 컨테이너 `iCloud.io.github.swpark3179.DayGrid`)에 저장된다. 사용자 iCloud 용량을 쓰고, 개발자는 볼 수 없다.
- iCloud에 로그인하지 않았으면 기기에만 저장한다. 로그인하면 그때부터 맞춘다.

## 4. 스크린샷과 미리보기 다시 만들기
- 문구: `appstore/screenshots.json`(제목은 `\n`으로 줄을 나눈다)
- 화면과 순서: `DayGridUITests/AppStoreTests.swift`의 `AppStoreScreenshotTests`(01–09). 이름은 `screenshots.json`의 `raw`와 같아야 한다.
- 영상의 동작: 같은 파일의 `AppStorePreviewTests`
- 이 파일들을 바꾼 PR에서 워크플로가 저절로 돈다. 수동으로는 **Actions → App Store assets → Run workflow**.
- 만드는 방식
  - 화면: 6.9형 시뮬레이터(iPhone 17 Pro Max)에서 UI 테스트가 찍는다. 날짜(2026-10-19)와 샘플 데이터는 다른 UI 테스트와 같다.
  - 문구·기기 틀: `scripts/appstore/compose_screenshots.py`(Pillow, Pretendard 글꼴)
  - 영상: 시뮬레이터 밖의 `scripts/appstore/record_previews.py`가 테스트의 신호에 맞춰 녹화하고, `encode_previews.py`가 규격을 맞춘다.
- 로컬에서 문구만 바꿔 볼 때(글꼴은 워크플로의 주소에서 받는다):

```bash
python3 scripts/appstore/compose_screenshots.py --config appstore/screenshots.json --raw <화면 폴더> --fonts <글꼴 폴더> --out build/app-store-assets/screenshots
```

## 5. 심사 전 확인
- [ ] 지원 URL과 개인정보 처리방침 URL이 열린다(Pages 배포).
- [ ] 1.0 TestFlight 빌드를 기기에서 확인했다(`docs/DEVICE_CHECKLIST.md` 19장: 설정의 링크, 동기화).
- [ ] 설정 → 동기화에 오류가 없다(Production 스키마).
- [ ] 스크린샷 6.3형 칸에 최소 1장, 6.9형 칸에도 넣었다.
- [ ] 앱 개인정보: 데이터 수집 안 함
- [ ] 연령 등급 4+, 가격과 국가
- [ ] App Review 연락처를 넣었다.
- [ ] 실기기 화면 녹화를 첨부했고, 메모의 `[[...]]`를 모두 채웠다(6번).
- [ ] 고른 빌드가 "잘못된 바이너리"가 아니다. 그 빌드를 서명한 배포 인증서를 폐기하지 않았다(6번).

## 6. 심사 답변: Guideline 2.1 Information Needed
2026-11-02 첫 제출에서 받았다. 버그 때문이 아니라 새 앱에 정보를 요청하는 것이다. 메모와 녹화를 넣고 같은 빌드로 다시 제출하면 된다.
요청한 6가지와 넣을 곳은 아래와 같다.

| 요청 | 넣을 곳 |
|---|---|
| 1. 실기기 화면 녹화(최신 iOS, 앱 실행부터) | App Review에 관한 정보의 첨부 파일. 안 되면 메모에 링크 |
| 2. 목적과 대상 사용자 | 메모 2번 |
| 3. 주요 기능 사용법(로그인, 샘플 파일) | 메모 3번. 계정이 없어 로그인 정보가 없다 |
| 4. 외부 서비스 | 메모 4번 |
| 5. 지역 차이 | 메모 5번 |
| 6. 규제 산업 서류 | 메모 6번. 해당 없음 |

메모에는 Apple 안내대로 테스트한 기기와 iOS 버전도 적는다(마지막 줄).

### 녹화 준비
- iPhone을 최신 iOS로 올린다(설정 → 일반 → 소프트웨어 업데이트). 기기 모델과 iOS 버전은 설정 → 일반 → 정보에서 보고 메모의 `[[...]]`에 넣는다.
- 심사에 올린 빌드를 TestFlight에서 설치한다. 설정 → 정보의 버전이 ASC에서 고른 빌드와 같은지 본다.
- 제어 센터에 "화면 기록"이 없으면 더한다(제어 센터 → 왼쪽 위 + → 컨트롤 추가 → 화면 기록).
- 집중 모드(방해 금지)를 켠다. 다른 앱 알림이 녹화에 나오지 않게 한다.
- 녹화에 보이는 일정은 심사와 상관없다. 보이기 싫은 일정이 있으면 녹화 전에 정리한다.
- 연락처 가져오기는 실제 연락처 이름이 나오므로 녹화에서 뺀다. 생일은 직접 하나 더한다.
- 앱이 떠 있으면 앱 전환기에서 위로 밀어 끈다. 녹화는 앱을 여는 순간부터 찍혀야 한다.

### 녹화 순서(3–5분)
천천히, 한 동작이 끝난 걸 보이고 다음으로 간다.
1. 홈 화면에서 화면 기록을 켜고, DayGrid 아이콘을 눌러 연다.
2. 달력: 좌우로 밀어 다음 달을 보고, 제목(연·월)을 눌러 달을 고른 뒤 오늘로 돌아온다.
3. 달력 위쪽의 + → 제목, "시간 지정", 카테고리, 알림 칩 하나 → 알림 권한 창에서 허용 → 저장. 달력에 막대가 생긴다.
4. 날짜를 꾹 눌러 사흘쯤 끌고 놓는다 → 제목을 적고 저장. 기간 일정이 생긴다.
5. 날짜를 눌러 하루 상세를 연다.
   - 일정을 꾹 눌러 다른 날 위에 놓는다.
   - 옮긴 날을 열어 그 행을 밀어 삭제하고, "실행 취소"를 누른다.
6. 일정을 열어 본문에 체크리스트 두 줄(`- [ ] 할일`)을 적고 미리보기에서 하나를 체크한다.
7. 나중에 탭: 할일 두세 개를 적고 엔터. 하나를 꾹 눌러 덮개 달력의 날짜 위에 놓는다. 달력 탭에 그 날로 들어간 게 보인다.
8. 반복 탭: + → 매일 반복 할일을 만들고 체크한다.
9. 설정
   - 생일 → + → 음력 생일을 하나 더한다. 목록에 D-day가 보인다.
   - 동기화(iCloud 상태)를 보여 준다.
   - 정보의 "개인정보 처리방침"을 눌러 Safari에서 열린 것을 보이고 돌아온다.
10. (선택) 홈 화면으로 나가 잠금화면 위젯 "남은 반복 할일"을 보여 준다.
11. 화면 기록을 끈다. 사진 앱에서 앞뒤의 군더더기만 자른다. 앱을 여는 장면은 남긴다.

녹화에서 이상한 동작이나 멈춤이 보이면 올리지 말고 먼저 고친다. 심사자도 실기기에서 같은 동작을 해 본다.
녹화 전에 `docs/DEVICE_CHECKLIST.md`의 7장(iCloud)과 19장을 이 빌드로 확인해 두면 좋다. 저장소에는 아직 체크되지 않았다.

### ASC에 넣고 다시 제출
1. 녹화 파일을 ASC를 여는 기기로 옮긴다. Mac이 없으면 iCloud 사진(icloud.com)에서 PC로 받거나, iPhone Safari에서 ASC를 열어 사진 보관함에서 바로 고른다.
2. ASC → 앱 → DayGrid → iOS 앱 1.0 → **App Review에 관한 정보**
   - 메모: `notes.txt`를 붙인다. `[[...]]`를 채운 뒤 4000바이트를 넘지 않는지 본다(`python3 scripts/appstore/check_metadata.py`).
   - 첨부 파일: 녹화 파일을 올린다.
   - 올라가지 않으면(크기, 형식) 로그인 없이 볼 수 있는 링크를 만든다(iCloud Drive "링크가 있는 모든 사람", Google Drive, YouTube 일부 공개). 메모 1번의 "Attached in App Review Information > Attachment."를 "Video: <링크>"로 바꾼다.
3. 저장한 뒤 거절 메시지(App Review 메시지)에 짧게 답한다. 같은 내용을 메모에 넣었다고 알린다.

```text
Hello, thank you for the review.
We added all requested information to the Notes field of App Review Information, and attached a screen recording captured on a physical iPhone running the latest iOS, starting from app launch.
DayGrid has no accounts, no user-generated content shared with others, and no paid features or in-app purchases.
Thank you.
```

4. 버전 페이지에서 다시 심사에 제출한다. 빌드가 "잘못된 바이너리"가 아니면 바꾸지 않아도 된다. 앱을 고쳤다면 새 TestFlight 빌드를 올려 골라야 한다.

### 1.0이 "잘못된 바이너리"가 됐을 때(2026-11-02)
- 원인: 예전 TestFlight 워크플로가 업로드를 마친 뒤 배포 인증서를 폐기했다.
  - Apple은 폐기한 인증서로 서명한 빌드를 Invalid Binary로 표시한다([Certificates overview](https://developer.apple.com/support/certificates/) "Expired or revoked certificates").
  - TestFlight는 Apple이 다시 서명해 내보내므로 그대로 돈다. 그래서 TestFlight만 보면 문제가 없어 보인다.
  - 이 빌드는 다시 쓸 수 없다. 앱을 고칠 것은 없고, 새로 서명한 빌드만 있으면 된다.
- 제출이 "해결되지 않은 문제"로 남는 것도 같은 이유다. 쓸 수 있는 빌드로 다시 제출해야 넘어간다.
- 할 일
  1. 워크플로 수정(인증서를 Secrets에 두고 폐기하지 않는다)을 머지한다.
  2. `docs/TESTFLIGHT.md` 5-1대로 `SECRETS_TOKEN`을 넣는다.
  3. **Actions → TestFlight → Run workflow**(main). 빌드 번호는 실행 번호라 저절로 올라간다. 처리가 끝날 때까지 10–30분 기다린다.
  4. ASC → 1.0 → **빌드**에서 예전 빌드를 빼고 새 빌드를 고른 뒤 저장한다.
  5. 메모와 첨부가 그대로 있는지 보고, **심사에 추가** → **심사에 제출**한다. App Review 메시지에도 새 빌드로 다시 냈다고 짧게 답한다.
- 심사가 끝날 때까지(그리고 그 뒤에도) developer.apple.com에서 Apple Distribution 인증서를 폐기하지 않는다.
