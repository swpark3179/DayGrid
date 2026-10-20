/// `@AppStorage` 키.
enum AppSettings {
    /// 주 시작 요일. 1 = 일요일(기본), 2 = 월요일.
    static let firstWeekdayKey = "firstWeekday"

    /// 생일 알림. -1 = 끔, 0 = 당일, n = 당일과 n일 전
    static let birthdayReminderKey = "birthdayReminderDays"

    /// 하루 상세 보기 방식(`DayDetailStyle`). UI 테스트는 실행 인자 `-dayDetailStyle timeline`으로 켠다.
    static let dayDetailStyleKey = "dayDetailStyle"

    /// 타임라인의 업무 시간(자정부터 지난 분). 기본 09:00–18:00
    static let workdayStartMinuteKey = "workdayStartMinute"
    static let workdayEndMinuteKey = "workdayEndMinute"
    static let defaultWorkdayStartMinute = 9 * 60
    static let defaultWorkdayEndMinute = 18 * 60

    static func birthdayReminderDays(_ value: Int) -> [Int] {
        switch value {
        case ..<0: []
        case 0: [0]
        default: [0, value]
        }
    }
}

/// 하루 상세 보기 방식.
enum DayDetailStyle: String, CaseIterable, Identifiable {
    /// 종일·기간, 시간, 할일 목록
    case list
    /// 시간 일정은 업무 시간 타임라인에, 나머지는 그 아래 목록에
    case timeline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: "목록"
        case .timeline: "타임라인"
        }
    }
}
