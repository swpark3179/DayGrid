/// `@AppStorage` 키.
enum AppSettings {
    /// 주 시작 요일. 1 = 일요일(기본), 2 = 월요일.
    static let firstWeekdayKey = "firstWeekday"

    /// 생일 알림. -1 = 끔, 0 = 당일, n = 당일과 n일 전
    static let birthdayReminderKey = "birthdayReminderDays"

    static func birthdayReminderDays(_ value: Int) -> [Int] {
        switch value {
        case ..<0: []
        case 0: [0]
        default: [0, value]
        }
    }
}
