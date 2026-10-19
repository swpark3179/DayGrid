import DayGridCore

/// UI 테스트가 실행 인자로 넘기는 옵션. 스크린샷이 실행할 때마다 같게 나오도록 날짜와 데이터를 고정한다.
///
/// - `-UITestFixedToday yyyy-MM-dd`: 오늘 날짜를 고정한다.
/// - `-UITestSeedData`: 샘플 데이터를 넣고 시작한다.
struct LaunchOptions: Equatable {
    var fixedToday: LocalDate?
    var seedSampleData = false

    init(arguments: [String]) {
        if let flagIndex = arguments.firstIndex(of: "-UITestFixedToday"),
           arguments.indices.contains(flagIndex + 1) {
            fixedToday = LocalDate(iso8601: arguments[flagIndex + 1])
        }
        seedSampleData = arguments.contains("-UITestSeedData")
    }
}
