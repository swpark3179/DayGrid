# 잠금화면 위젯 준비

잠금화면 위젯 "남은 반복 할일"은 주기가 돌아왔는데 아직 하지 않은 반복 할일을 보여줍니다. 완료한 것은 숨깁니다.
- 앱과 위젯은 **App Group** 폴더로 반복 할일 요약을 주고받습니다.
- App Group과 위젯용 App ID를 한 번 등록해야 TestFlight 빌드를 올릴 수 있습니다. 1–3번은 처음 한 번만 하면 됩니다.

## 1. App Group 만들기
1. [developer.apple.com/account](https://developer.apple.com/account) → **Certificates, IDs & Profiles** → **Identifiers** → `+`
2. **App Groups**를 고르고 Continue를 누릅니다.
3. 다음과 같이 입력하고 Continue → Register를 누릅니다.
   - Description: `DayGrid`
   - Identifier: `group.io.github.swpark3179.DayGrid`

## 2. 앱 App ID에 App Group 켜기
1. **Identifiers** 목록에서 필터를 **App IDs**로 바꾸고 `io.github.swpark3179.DayGrid`를 엽니다.
2. **App Groups**를 체크하고 **Configure**(또는 Edit)를 누릅니다. 1번의 `group.io.github.swpark3179.DayGrid`를 체크하고 Continue를 누릅니다.
3. **Save**를 누르고, 프로파일 안내가 나오면 Confirm을 누릅니다.
   - iCloud와 Push Notifications는 켜 둔 그대로 둡니다.

## 3. 위젯 App ID 만들기
1. **Identifiers** → `+` → **App IDs** → **App** → Continue
2. 다음과 같이 입력합니다.
   - Description: `DayGrid Widgets`
   - Bundle ID: **Explicit**, `io.github.swpark3179.DayGrid.Widgets`
3. Capabilities에서 **App Groups**를 체크하고 Configure → `group.io.github.swpark3179.DayGrid` → Continue → Register를 누릅니다.

App Store Connect에 앱을 새로 만들 필요는 없습니다. 위젯은 DayGrid 앱 안에 들어갑니다.

## 4. TestFlight로 확인
- **Actions** → **TestFlight** → **Run workflow**로 새 빌드를 올립니다.
- iPhone 잠금화면을 길게 누릅니다 → **사용자화** → 잠금화면 → 시계 아래 위젯 칸 → **DayGrid** → "남은 반복 할일"을 추가합니다.
  - 모양: 목록형, 동그라미(개수), 시계 위 한 줄
- `docs/DEVICE_CHECKLIST.md` 10장을 따라 확인합니다.

## 문제가 생기면
- **TestFlight "Create signing certificate and profiles" 단계 오류**
  - 워크플로가 서명 전에 App ID를 모두 확인합니다. 고칠 것을 한꺼번에 보여 줍니다.
  - "App ID io.github.swpark3179.DayGrid.Widgets가 developer.apple.com에 없다" → 3번을 합니다.
  - "App ID …에 App Groups가 꺼져 있다" → 앱이면 2번, 위젯이면 3번을 합니다.
  - "… 프로파일에 없는 entitlement: com.apple.security.application-groups"
    - App Groups는 켜져 있지만 그룹이 체크되지 않은 상태입니다.
    - 그 App ID의 App Groups → Configure(또는 Edit)에서 `group.io.github.swpark3179.DayGrid`를 체크하고 Save합니다.
    - 두 App ID 모두 같은 그룹이어야 합니다.
- **위젯이 "남은 반복 할일 없음"만 보인다**
  - 앱을 한 번 열면 요약을 다시 씁니다.
  - 그래도 같으면 App Group 설정(2–3번)을 확인합니다. 앱과 위젯이 같은 그룹을 써야 요약을 읽습니다.
- **체크했는데 위젯이 늦게 바뀐다**: 위젯 갱신 시점은 iOS가 정하므로 몇 초에서 몇 분 늦을 수 있습니다.
