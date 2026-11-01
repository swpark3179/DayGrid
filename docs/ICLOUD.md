# iCloud 동기화 준비

DayGrid는 iCloud(CloudKit) 개인 데이터베이스로 일정, 할일, 카테고리, 생일, 개인 휴일, 반복 할일을 동기화합니다. 같은 Apple ID를 쓰는 기기끼리 맞춰지고, 앱을 지웠다가 다시 설치해도 데이터가 돌아옵니다.

## 동작 방식(사용자가 보는 것)
- **앱 안에서 로그인하지 않는다.** iPhone **설정 → [이름]**에 로그인한 Apple 계정의 iCloud를 그대로 쓴다. 회원가입, Sign in with Apple, 앱 계정이 없다.
- **저장 위치**: 그 Apple 계정의 iCloud **개인 데이터베이스**(CloudKit private DB, 컨테이너 `iCloud.io.github.swpark3179.DayGrid`).
  - 그 사용자만 읽고 쓸 수 있다. 개발자도 CloudKit Console에서 내용을 볼 수 없다(스키마만 본다).
  - 사용자의 iCloud 저장 공간을 쓴다. 글자 데이터라 아주 작다. 가득 차면 설정에 "iCloud 저장 공간이 부족합니다"가 보인다.
- **저장 순서**: 앱은 SwiftData(`ModelConfiguration(cloudKitDatabase: .private(…))`)로 기기에 먼저 저장한다. 시스템(`NSPersistentCloudKitContainer`)이 뒤에서 iCloud로 올리고 받는다. 다른 기기의 변경은 조용한 푸시(`remote-notification`)로 알게 된다.
- **iCloud에 로그인하지 않았거나, iCloud를 사용하는 앱 목록에서 DayGrid를 껐을 때**: 앱은 그대로 쓸 수 있고 기기에만 저장한다. 설정 → 동기화에 "iCloud에 로그인되어 있지 않습니다"가 보인다.
  - 로그인하지 않은 채 적은 데이터가 나중에 로그인하면 함께 올라가는지는 아직 기기에서 확인하지 않았다(`docs/DEVICE_CHECKLIST.md` 19-5).
- **로그아웃하거나 DayGrid의 iCloud를 끌 때**: iOS가 이 기기의 DayGrid 데이터를 지운다. Apple이 정한 동작이다(Apple 개발자 포럼 DTS 답변: "Turning off iCloud for an app is equivalent to signing out of the account").
  - iCloud에 이미 올라간 데이터는 남아 있어서, 다시 로그인하거나 켜면 돌아온다.
  - 아직 올라가지 않은 최근 변경은 사라질 수 있다.
- **앱을 지울 때**: 기기의 데이터만 지워지고 iCloud에는 남는다. 다시 설치하면 돌아온다. 모두 지우려면 iPhone 설정 → [이름] → iCloud → 저장 공간 관리에서 DayGrid의 데이터를 지운다.
- **TestFlight와 App Store 빌드**: 둘 다 Production 환경을 쓴다. 같은 Apple 계정이면 같은 데이터를 본다.
- 다른 사람과 나누는 기능은 없다(개인 DB만 쓴다).

TestFlight로 받은 앱은 CloudKit의 **Production** 환경을 씁니다.
- Production에는 데이터 구조(스키마)가 자동으로 생기지 않습니다.
- 그래서 아래 순서로 한 번 준비해야 동기화가 시작됩니다. 1–3번은 처음 한 번만 하면 됩니다.
- 모두 웹 브라우저에서 할 수 있습니다.

## 1. iCloud 컨테이너 만들기
1. [developer.apple.com/account](https://developer.apple.com/account) → **Certificates, IDs & Profiles** → **Identifiers** → `+`
2. **iCloud Containers**를 고르고 Continue를 누릅니다.
3. 다음과 같이 입력하고 Continue → Register를 누릅니다.
   - Description: `DayGrid`
   - Identifier: `iCloud.io.github.swpark3179.DayGrid`

## 2. App ID에서 iCloud와 푸시 켜기
1. **Identifiers** 목록 오른쪽 위의 필터를 **App IDs**로 바꾸고, `io.github.swpark3179.DayGrid`를 엽니다.
2. **Capabilities**에서 두 가지를 켭니다.
   - **iCloud**: CloudKit을 포함하는 선택지(Include CloudKit support)를 고릅니다. 그다음 **Configure**(또는 Edit)를 눌러 1번에서 만든 `iCloud.io.github.swpark3179.DayGrid`를 체크하고 Continue를 누릅니다.
   - **Push Notifications**: 체크만 합니다. 다른 기기의 변경을 조용한 알림으로 받는 데 씁니다. 인증서는 만들 필요가 없습니다.
3. 오른쪽 위 **Save**를 누릅니다. 프로파일이 무효가 된다는 안내가 나오면 Confirm을 누릅니다. TestFlight 워크플로가 다음 실행 때 새로 만듭니다.

## 3. CloudKit 관리 토큰 등록
1. [CloudKit Console](https://icloud.developer.apple.com)에 같은 개발자 계정으로 들어갑니다.
2. 오른쪽 위 계정 메뉴의 **Settings**에서 관리 토큰(**Management Tokens**) → `+`를 누릅니다.
3. 이름을 `GitHub Actions`로 정하고 만듭니다. 토큰은 **한 번만** 보이니 바로 복사합니다. 유효 기간은 1년입니다.
4. GitHub 저장소 → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**에서 등록합니다.
   - 이름: `CLOUDKIT_MANAGEMENT_TOKEN`
   - 값: 복사한 토큰

토큰은 저장소 코드나 채팅에 붙여넣지 말고 GitHub Secrets에만 넣으세요. `APPLE_TEAM_ID` Secret은 TestFlight 준비 때 넣은 것을 그대로 씁니다.

## 4. 스키마 올리기
1. 저장소 → **Actions** → **CloudKit schema** → **Run workflow** → mode **import** → Run
   - 실행 로그에 Development 스키마의 전후가 찍힙니다.
   - Claude에게 "CloudKit 스키마 올려줘"라고 해도 됩니다. 처음에는 Claude가 mode **check**로 형식부터 확인할 수 있습니다.
2. CloudKit Console → **CloudKit Database** → 컨테이너 `iCloud.io.github.swpark3179.DayGrid`를 엽니다.
3. 왼쪽 아래 **Deploy Schema Changes…**를 누르고, Production에 더해질 레코드 타입(`CD_Item` 등 6개)을 확인한 뒤 **Deploy**를 누릅니다.
   - Production에 배포한 필드는 지우거나 타입을 바꿀 수 없습니다. 더하는 것만 됩니다.
   - **import만 하고 이 단계를 빼먹으면** TestFlight 빌드에서 "동기화 오류"가 납니다. 1번만으로는 Production이 바뀌지 않습니다.
4. 배포했는지는 같은 워크플로를 mode **check**로 실행해 확인합니다.
   - "Compare with the Production schema" 단계와 실행 요약에 Production에 없는 레코드 타입이나 필드가 나옵니다.
   - "레코드 타입 7개와 필드가 모두 있다"가 나오면 배포된 것입니다.

## 5. TestFlight로 확인
- **Actions** → **TestFlight** → **Run workflow**로 새 빌드를 올립니다(`docs/TESTFLIGHT.md`).
- 설치한 뒤 `docs/DEVICE_CHECKLIST.md` 7장을 따라 확인합니다.
- 앱의 **설정 → 동기화 → iCloud**에서 상태를 볼 수 있습니다.

## 문제가 생기면
- **TestFlight "Create signing certificate and profiles" 단계에서 "프로파일에 없는 entitlement: com.apple.developer.icloud-container-identifiers"**
  - App ID에 iCloud는 켜져 있지만 컨테이너가 체크되지 않은 상태입니다. 로그에 `'com.apple.developer.icloud-container-identifiers': []`처럼 빈 목록이 보입니다.
  - 2번의 **iCloud → Configure(또는 Edit)**에서 `iCloud.io.github.swpark3179.DayGrid`를 체크하고 **Save**까지 누릅니다.
  - 컨테이너 연결은 API로 할 수 없어서 이 화면에서만 할 수 있습니다.
- **TestFlight 내보내기 단계에서 다른 iCloud나 프로파일 오류**: 1–2번을 확인합니다.
- **설정에 "iCloud에 로그인되어 있지 않습니다"**
  - iPhone 설정 → [이름] → iCloud에 로그인되어 있는지 확인합니다.
  - "iCloud를 사용하는 앱"에서 DayGrid가 켜져 있는지 확인합니다.
- **설정에 "iCloud(Production)의 데이터 구조가 앱과 맞지 않습니다"**
  - 원인은 Production 스키마가 없거나 모델과 다른 것입니다. 괄호 안에 서버 문구(예: `Cannot create new type CD_Item in production schema`)가 보입니다.
  - 4번(import → Deploy)을 다시 하고, 4-4의 check로 확인합니다.
- **설정에 "동기화 오류: 작업을 완료할 수 없습니다. (CKErrorDomain 오류 2.)"**
  - 2026-10-20까지의 빌드가 보여주던 문구입니다. 오류 2는 "묶음 실패(partialFailure)"라서, 진짜 원인은 그 안의 레코드별 오류에 있습니다.
  - 2026-10-20에 확인했을 때 Production에는 `Users`만 있고 DayGrid 레코드 타입 6개가 없었습니다. 4-3(Deploy)을 하면 해결됩니다.
  - 새 빌드는 안쪽 오류를 펼쳐서 원인(예: `serverRejectedRequest(15): …`)을 보여줍니다.
- **설정에 "iCloud가 이 기기의 변경을 받지 않았습니다(partialFailure)"** (복사한 내용이 `iCloud 보내기 실패 … partialFailure(2)`뿐일 때)
  - 2026-10-21 빌드 10에서 본 모양입니다. 오류에 레코드별 원인이 들어 있지 않았습니다.
  - 같은 날 4-4의 check로 확인했을 때 Production에는 여전히 `Users`만 있었습니다. 4-3(Deploy)을 하면 해결됩니다.
  - 새 빌드는 실패한 시각의 앱 기록(CloudKit·Core Data 로그)도 읽습니다. 원인을 찾으면 위의 "데이터 구조가 앱과 맞지 않습니다" 같은 안내로 바뀝니다.
- **복사한 내용의 "앱 기록:" 아래에 `invalidArguments(12): Cannot create new type CD_… in production schema`가 있을 때**
  - 2026-10-21에 본 모양입니다(`CD_PersonalHoliday` ×2). Production에 그 레코드 타입이 없다는 뜻입니다. 앱은 맞게 동작하고 있습니다.
  - 같은 날 4-4의 check(실행 #4, 09:36Z)에서도 Production에는 `Users`만 있었습니다. 4-3(Deploy)을 하면 해결됩니다.
  - 레코드 타입 이름은 그때 보내던 데이터에 따라 바뀝니다. 하나만 보여도 6개를 모두 배포해야 합니다.
- **그 밖의 "동기화 문제"**
  - 설정 → 동기화의 **오류 내용 복사**를 눌러 복사한 내용을 Claude에게 붙여 넣어 주세요. 실패하고 1–2초 뒤에 복사하면 앱 기록까지 들어갑니다.
  - 바깥 오류부터 안쪽 오류까지 한 줄씩(코드 이름, 서버 문구, userInfo 키) 들어 있습니다.
  - "앱 기록:" 아래에는 그 시각에 CloudKit이 남긴 오류가 있습니다. 오류를 찾지 못하면 기록 줄을 몇 줄 그대로 넣으므로, 일정 제목 같은 내용이 섞였는지 붙여 넣기 전에 확인해 주세요.
- **설정에 "iCloud 컨테이너 설정이 맞지 않습니다"**: 1–2번(컨테이너, App ID의 iCloud 컨테이너 체크)을 확인합니다.
- **CloudKit schema 워크플로에서 인증 오류**: 토큰이 만료됐거나 잘못 붙여넣은 경우입니다. 3번에서 새 토큰을 만들어 Secret을 바꿉니다.
- **데이터가 이상할 때**
  - 앱이 처음 iCloud를 켤 때 기존 저장소를 이 기기의 `Application Support/Backups/pre-icloud`에 한 번 복사해 둡니다.
  - 지금은 앱에서 되살리는 기능이 없습니다. 필요하면 Claude에게 복구 기능을 부탁하세요.

## 앞으로 모델을 바꿀 때(개발 규칙)
1. 모델을 바꾸면 `CloudKitSchemaTests`가 실패합니다. 실패 메시지에 나온 새 내용으로 `cloudkit/DayGrid.ckdb`를 바꿉니다.
2. PR을 머지한 뒤 4번(import → Deploy)을 합니다.
3. 그다음에 TestFlight 빌드를 올립니다. 순서가 바뀌면 새 필드를 쓰는 기기에서 동기화가 멈춥니다.
4. 이미 배포한 필드는 이름을 바꾸거나 지우지 않습니다. 필요하면 새 필드를 더합니다.
