import DayGridCore

/// UI 테스트가 실행 인자로 넘기는 옵션. 스크린샷이 실행할 때마다 같게 나오도록 날짜와 데이터를 고정한다.
///
/// - `-UITestFixedToday yyyy-MM-dd`: 오늘 날짜를 고정한다.
/// - `-UITestSeedData`: 메모리 전용 저장소에 샘플 데이터를 넣고 시작한다.
/// - `-UITestQuickAction addTask`: 홈 화면 퀵 액션으로 연 것처럼 시작한다.
///
/// 다크 모드는 설정 키를 인자 도메인으로 넘긴다(`-appearance dark`, `AppSettings.appearanceKey`).
///
/// 단위 테스트의 호스트로 뜰 때(`XCTestConfigurationFilePath`)와 UI 테스트에서는 iCloud 동기화를 쓰지 않는다.
struct LaunchOptions: Equatable {
    var fixedToday: LocalDate?
    var seedSampleData = false
    var quickAction: QuickAction?
    var isUnitTestHost = false

    /// iCloud(CloudKit)에 연결된 저장소를 쓸지
    var usesCloudSync: Bool { !seedSampleData && !isUnitTestHost }

    init(arguments: [String], environment: [String: String] = [:]) {
        isUnitTestHost = environment["XCTestConfigurationFilePath"] != nil
        fixedToday = Self.value(after: "-UITestFixedToday", in: arguments).flatMap { LocalDate(iso8601: $0) }
        seedSampleData = arguments.contains("-UITestSeedData")
        quickAction = Self.value(after: "-UITestQuickAction", in: arguments).flatMap { QuickAction(rawValue: $0) }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
