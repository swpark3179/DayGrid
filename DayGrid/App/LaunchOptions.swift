import DayGridCore

/// UI 테스트가 실행 인자로 넘기는 옵션. 스크린샷이 실행할 때마다 같게 나오도록 날짜와 데이터를 고정한다.
///
/// - `-UITestFixedToday yyyy-MM-dd`: 오늘 날짜를 고정한다.
/// - `-UITestSeedData`: 메모리 전용 저장소에 샘플 데이터를 넣고 시작한다.
/// - `-UITestColorScheme dark`: 다크 모드로 띄운다.
/// - `-UITestQuickAction addTask`: 홈 화면 퀵 액션으로 연 것처럼 시작한다.
struct LaunchOptions: Equatable {
    var fixedToday: LocalDate?
    var seedSampleData = false
    var forcesDarkAppearance = false
    var quickAction: QuickAction?

    init(arguments: [String]) {
        fixedToday = Self.value(after: "-UITestFixedToday", in: arguments).flatMap { LocalDate(iso8601: $0) }
        seedSampleData = arguments.contains("-UITestSeedData")
        forcesDarkAppearance = Self.value(after: "-UITestColorScheme", in: arguments) == "dark"
        quickAction = Self.value(after: "-UITestQuickAction", in: arguments).flatMap { QuickAction(rawValue: $0) }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
