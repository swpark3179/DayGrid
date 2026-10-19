# DayGrid

달력을 첫 화면으로 쓰는 iOS 개인 일정 앱입니다. 일정, 나중에 할일, 반복 할일, 공휴일과 생일, 미리알림을 한곳에서 관리합니다.

- 계획과 진행 현황: [docs/ROADMAP.md](docs/ROADMAP.md)
- 개발 규칙: [CLAUDE.md](CLAUDE.md)

## 빌드

Mac이 없어도 되도록 GitHub Actions에서 빌드합니다. PR을 올리면 CI가 테스트를 돌리고, 시뮬레이터 스크린샷을 `screenshots` 아티팩트로 올립니다.

Mac에서 직접 빌드할 때:

```sh
brew install xcodegen
xcodegen generate
open DayGrid.xcodeproj
```
