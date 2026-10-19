/// 해마다 돌아오는 생일(양력 또는 음력).
///
/// - 양력 2월 29일생은 평년에 2월 28일로 본다.
/// - 음력 윤달생은 그 해에 같은 윤달이 없으면 평달로 본다. 30일생은 그 달이 29일까지면 29일로 본다.
public struct Birthday: Hashable, Sendable {
    public var month: Int
    public var day: Int
    public var isLunar: Bool
    public var isLeapMonth: Bool

    public init(month: Int, day: Int, isLunar: Bool = false, isLeapMonth: Bool = false) {
        self.month = month
        self.day = day
        self.isLunar = isLunar
        self.isLeapMonth = isLunar && isLeapMonth
    }

    /// 양력 생일이면 양력 `year`, 음력 생일이면 음력 `year`의 생일 날짜. 계산할 수 없으면 `nil`.
    public func date(inYear year: Int) -> LocalDate? {
        guard (1...12).contains(month), day >= 1 else { return nil }
        if !isLunar {
            let day = min(day, LocalDate.numberOfDays(inMonth: month, year: year))
            return LocalDate(year: year, month: month, day: day)
        }
        let isLeap = isLeapMonth && KoreanLunarCalendar.leapMonth(inYear: year) == month
        guard let length = KoreanLunarCalendar.numberOfDays(year: year, month: month, isLeapMonth: isLeap) else { return nil }
        return KoreanLunarCalendar.solarDate(year: year, month: month, day: min(day, length), isLeapMonth: isLeap)
    }

    /// `range` 안의 생일 날짜(빠른 순).
    public func occurrences(in range: ClosedRange<LocalDate>) -> [LocalDate] {
        // 음력 12월 생일은 다음 양력 해 1~2월에 오므로 한 해 앞부터 본다.
        let years = (range.lowerBound.year - (isLunar ? 1 : 0))...range.upperBound.year
        return years.compactMap { date(inYear: $0) }.filter { range.contains($0) }.sorted()
    }

    /// `today` 또는 그 뒤의 첫 생일.
    public func nextOccurrence(onOrAfter today: LocalDate) -> LocalDate? {
        occurrences(in: today...today.adding(days: 400)).first
    }

    /// "10월 19일" 또는 "음력 8월 15일", "음력 윤6월 3일"
    public var koreanText: String {
        guard isLunar else { return "\(month)월 \(day)일" }
        return "음력 \(isLeapMonth ? "윤" : "")\(month)월 \(day)일"
    }
}

/// 다가오는 생일 목록. 오늘부터 `days`일 안의 생일을 가까운 순으로 정렬한다.
public struct UpcomingBirthday<ID: Hashable & Sendable>: Hashable, Sendable {
    public let id: ID
    public let date: LocalDate
    /// 오늘이면 0.
    public let daysLeft: Int

    public static func list(
        _ birthdays: [(id: ID, birthday: Birthday)],
        today: LocalDate,
        within days: Int = 30
    ) -> [UpcomingBirthday] {
        birthdays
            .compactMap { entry -> UpcomingBirthday? in
                guard let next = entry.birthday.nextOccurrence(onOrAfter: today) else { return nil }
                let left = today.days(until: next)
                return left <= days ? UpcomingBirthday(id: entry.id, date: next, daysLeft: left) : nil
            }
            .sorted { $0.daysLeft < $1.daysLeft }
    }

    /// "오늘", "D-3"
    public var koreanDDay: String {
        daysLeft == 0 ? "오늘" : "D-\(daysLeft)"
    }
}
