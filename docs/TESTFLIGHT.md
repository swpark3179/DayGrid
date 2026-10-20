# TestFlight로 iPhone에 설치하기

Mac 없이 GitHub Actions에서 앱을 빌드하고, 서명해서 TestFlight에 올립니다.

- 서명은 App Store Connect API 키로 합니다. 워크플로가 실행할 때마다 배포 인증서와 프로파일을 만들고, 끝나면 지웁니다. 인증서 파일(.p12)을 직접 만들 필요가 없습니다.
  - 그래서 developer.apple.com의 Certificates와 Profiles 목록에 "DayGrid CI …" 항목이 실행 중에만 잠깐 생깁니다.
  - 인증서를 폐기해도 이미 올린 TestFlight 빌드에는 영향이 없습니다.
- 아래 1~5번은 처음 한 번만 하면 됩니다. 모두 웹 브라우저에서 할 수 있습니다.

## 1. 번들 ID 등록
1. [developer.apple.com/account](https://developer.apple.com/account) → **Certificates, IDs & Profiles** → **Identifiers** → `+`
2. **App IDs** → **App** 선택 → Continue
3. 다음과 같이 입력하고 Continue → Register를 누릅니다. Capabilities는 여기서 켜지 않습니다. iCloud는 나중에 `docs/ICLOUD.md`대로 켭니다.
   - Description: `DayGrid`
   - Bundle ID: **Explicit**, `io.github.swpark3179.DayGrid`

## 2. App Store Connect에 앱 만들기
1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **앱** → `+` → **신규 앱**
2. 다음과 같이 입력하고 생성합니다.
   - **플랫폼:** iOS
   - **이름:** `DayGrid`. App Store 전체에서 고유해야 하므로, 이미 쓰이고 있으면 `DayGrid 달력`처럼 바꿉니다. 나중에 바꿀 수 있습니다.
   - **기본 언어:** 한국어
   - **번들 ID:** 1번에서 만든 `io.github.swpark3179.DayGrid`
   - **SKU:** `daygrid`(아무 값이나 가능)
   - **사용자 액세스:** 전체 액세스

## 3. App Store Connect API 키 만들기
1. App Store Connect → **사용자 및 액세스** → **통합** 탭 → **App Store Connect API** → **팀 키** → `+`
2. 다음과 같이 입력하고 생성합니다.
   - **이름:** `GitHub Actions`
   - **액세스:** **관리(Admin)**. 배포 인증서와 프로파일을 만들려면 Admin 권한이 필요합니다.
3. 생성된 키 행에서 다음 세 가지를 확보합니다.
   - **키 ID**(예: `ABCD123456`)
   - 화면 위쪽에 있는 **Issuer ID**(UUID 형식)
   - **API 키 다운로드** → `AuthKey_키ID.p8`. 이 파일은 **한 번만** 받을 수 있으니 안전한 곳에 보관하세요.

## 4. 팀 ID 확인
[developer.apple.com/account](https://developer.apple.com/account) → **Membership details** → **Team ID**(10자, 예: `A1B2C3D4E5`)

## 5. GitHub Secrets 등록
저장소 → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**에서 아래 4개를 만듭니다.

| 이름 | 값 |
|---|---|
| `APPLE_TEAM_ID` | 4번의 Team ID |
| `ASC_KEY_ID` | 3번의 키 ID |
| `ASC_ISSUER_ID` | 3번의 Issuer ID |
| `ASC_PRIVATE_KEY` | `.p8` 파일을 메모장으로 열어 `-----BEGIN PRIVATE KEY-----`부터 `-----END PRIVATE KEY-----`까지 전부 붙여넣기 |

이 값들은 저장소 코드나 채팅에 붙여넣지 마세요. GitHub Secrets에만 넣습니다.

## 6. 빌드 올리기
- 저장소 → **Actions** → **TestFlight** → **Run workflow**를 누르고 브랜치는 `main`을 고릅니다.
  - Claude에게 "TestFlight에 올려줘"라고 해도 됩니다.
- 15~20분쯤 걸립니다. 빌드 번호는 실행할 때마다 1씩 올라갑니다.
- **upload**를 끄고 실행하면 서명까지만 하고 올리지 않습니다. 서명 설정을 바꾼 뒤 확인할 때 씁니다.
- 끝나면 App Store Connect가 빌드를 처리하는 데 10~30분이 더 걸립니다.

## 7. iPhone에 설치
1. App Store Connect → 앱 → **TestFlight** → **내부 테스트** 옆 `+`
2. 그룹 이름(예: `나`)을 정하고, 테스터에 본인 Apple ID를 추가합니다. 빌드가 처리되면 그룹에 빌드를 추가합니다.
3. iPhone에서 App Store의 **TestFlight** 앱을 설치하고, 초대 메일이나 TestFlight 앱에서 DayGrid를 설치합니다.
4. 이후에는 새 빌드를 올릴 때마다 TestFlight 앱에 업데이트가 뜹니다.

## 문제가 생기면
- **"GitHub Secret … is not set"**: 5번의 Secret 이름 철자를 확인합니다.
- **"Create signing certificate and profiles" 단계에서 403 같은 권한 오류**: 3번 키의 액세스가 **관리(Admin)**인지 확인합니다.
- **"배포 인증서를 더 만들 수 없다(한도)"**: developer.apple.com → Certificates에서 쓰지 않는 Apple Distribution 인증서를 폐기(Revoke)합니다.
- **"App ID … 에 iCloud(또는 App Groups)가 꺼져 있다"**, **"프로파일에 없는 entitlement"**: `docs/ICLOUD.md` 2번, `docs/WIDGET.md` 2–3번대로 App ID를 설정합니다.
- **"No suitable application records were found"**: 2번의 앱 레코드와 번들 ID가 `io.github.swpark3179.DayGrid`로 일치하는지 확인합니다.
- 실패한 실행의 `testflight-logs` 아티팩트에 아카이브·내보내기 로그가 들어 있습니다.
