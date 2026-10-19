/// 한국 음력 날짜. `year`는 그 해 설날이 있는 양력 해다.
public struct LunarDate: Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let isLeapMonth: Bool

    public init(year: Int, month: Int, day: Int, isLeapMonth: Bool = false) {
        self.year = year
        self.month = month
        self.day = day
        self.isLeapMonth = isLeapMonth
    }
}

/// 한국천문연구원 기준 음력 ↔ 양력 변환. 표(`KoreanLunarData`)가 있는 1900~2049년 음력 해만 다룬다.
///
/// 운영체제의 중국 음력(`.chinese`)은 해에 따라 한국 음력과 하루씩 다르다(예: 2027년 설날).
public enum KoreanLunarCalendar {
    public static var supportedYears: ClosedRange<Int> {
        KoreanLunarData.firstYear...KoreanLunarData.lastYear
    }

    /// 그 해의 윤달. 없으면 `nil`.
    public static func leapMonth(inYear year: Int) -> Int? {
        guard let row = row(for: year), row.leapMonth > 0 else { return nil }
        return row.leapMonth
    }

    /// 그 달의 일수(29 또는 30). 없는 달이면 `nil`.
    public static func numberOfDays(year: Int, month: Int, isLeapMonth: Bool = false) -> Int? {
        guard let row = row(for: year), let index = monthIndex(month: month, isLeapMonth: isLeapMonth, leapMonth: row.leapMonth)
        else { return nil }
        return days(atIndex: index, bigMonths: row.bigMonths)
    }

    /// 음력 → 양력. 없는 날짜(윤달이 없는 해의 윤달, 29일까지인 달의 30일 등)면 `nil`.
    public static func solarDate(year: Int, month: Int, day: Int, isLeapMonth: Bool = false) -> LocalDate? {
        guard let row = row(for: year),
              let index = monthIndex(month: month, isLeapMonth: isLeapMonth, leapMonth: row.leapMonth),
              (1...days(atIndex: index, bigMonths: row.bigMonths)).contains(day),
              let newYear = LocalDate(yyyymmdd: row.newYear)
        else { return nil }
        let daysBefore = (0..<index).reduce(0) { $0 + days(atIndex: $1, bigMonths: row.bigMonths) }
        return newYear.adding(days: daysBefore + day - 1)
    }

    public static func solarDate(_ lunar: LunarDate) -> LocalDate? {
        solarDate(year: lunar.year, month: lunar.month, day: lunar.day, isLeapMonth: lunar.isLeapMonth)
    }

    /// 양력 → 음력. 표 범위 밖이면 `nil`.
    public static func lunarDate(from solar: LocalDate) -> LunarDate? {
        for year in supportedYears.reversed() {
            guard let row = row(for: year), let newYear = LocalDate(yyyymmdd: row.newYear), newYear <= solar else { continue }
            var remaining = newYear.days(until: solar)
            let months = monthSequence(leapMonth: row.leapMonth)
            for (index, month) in months.enumerated() {
                let length = days(atIndex: index, bigMonths: row.bigMonths)
                if remaining < length {
                    return LunarDate(year: year, month: month.month, day: remaining + 1, isLeapMonth: month.isLeap)
                }
                remaining -= length
            }
            return nil
        }
        return nil
    }

    // MARK: - 표 읽기

    private static func row(for year: Int) -> (newYear: Int, leapMonth: Int, bigMonths: Int)? {
        guard supportedYears.contains(year) else { return nil }
        return KoreanLunarData.years[year - KoreanLunarData.firstYear]
    }

    /// 그 해 달의 순서. 윤달은 그 달 바로 뒤에 온다.
    private static func monthSequence(leapMonth: Int) -> [(month: Int, isLeap: Bool)] {
        var months: [(month: Int, isLeap: Bool)] = []
        for month in 1...12 {
            months.append((month, false))
            if month == leapMonth {
                months.append((month, true))
            }
        }
        return months
    }

    private static func monthIndex(month: Int, isLeapMonth: Bool, leapMonth: Int) -> Int? {
        guard (1...12).contains(month) else { return nil }
        if isLeapMonth {
            return month == leapMonth ? month : nil
        }
        return leapMonth > 0 && month > leapMonth ? month : month - 1
    }

    private static func days(atIndex index: Int, bigMonths: Int) -> Int {
        (bigMonths >> index) & 1 == 1 ? 30 : 29
    }
}
