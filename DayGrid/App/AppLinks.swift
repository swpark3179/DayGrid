import Foundation

/// 앱 밖의 안내 페이지. GitHub Pages(`site/`, `.github/workflows/pages.yml`)에 있다.
/// App Store 등록 정보(`appstore/metadata/ko/*_url.txt`)와 같아야 한다(`scripts/appstore/check_metadata.py`가 확인한다).
enum AppLinks {
    static let website = URL(string: "https://swpark3179.github.io/DayGrid/")!
    static let support = URL(string: "https://swpark3179.github.io/DayGrid/support/")!
    static let privacyPolicy = URL(string: "https://swpark3179.github.io/DayGrid/privacy/")!
}
