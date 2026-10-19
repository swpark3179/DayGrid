import Foundation

/// 시간대와 무관한 달력상의 하루(양력).
///
/// 종일/기간 일정, 휴일, 생일처럼 "몇 시"가 아니라 "며칠"이 중요한 값은 모두 이 타입으로 다룬다.
/// 내부 계산은 1970-01-01 기준 일수(epoch day)로 하므로 시간대나 일광절약시간의 영향을 받지 않는다.
public struct LocalDate: Hashable, Sendable {
    public let year: Int
    /// 1...12
    public let month: Int
    /// 1...31
    public let day: Int

    /// 존재하지 않는 날짜(예: 2026-02-29)이면 `nil`.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month),
              (1...Self.numberOfDays(inMonth: month, year: year)).contains(day)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    private init(validatedYear year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }
}

// MARK: - 달력 규칙

extension LocalDate {
    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func numberOfDays(inMonth month: Int, year: Int) -> Int {
        switch month {
        case 2: isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    public var numberOfDaysInMonth: Int {
        Self.numberOfDays(inMonth: month, year: year)
    }

    /// 1 = 일요일 … 7 = 토요일 (Foundation `Calendar`의 weekday와 같은 규칙).
    public var weekday: Int {
        // 1970-01-01은 목요일(5)이다.
        let offset = (epochDay + 4) % 7
        return (offset < 0 ? offset + 7 : offset) + 1
    }

    public var firstDayOfMonth: LocalDate {
        LocalDate(validatedYear: year, month: month, day: 1)
    }

    public var lastDayOfMonth: LocalDate {
        LocalDate(validatedYear: year, month: month, day: numberOfDaysInMonth)
    }

    /// `year * 12 + (month - 1)`. 월 단위 페이지 번호로 쓴다.
    public var monthIndex: Int {
        year * 12 + (month - 1)
    }

    /// `monthIndex`가 가리키는 달의 1일.
    public init(firstDayOfMonthIndex index: Int) {
        let year = index >= 0 ? index / 12 : (index - 11) / 12
        self.init(validatedYear: year, month: index - year * 12 + 1, day: 1)
    }
}

// MARK: - 날짜 산술

extension LocalDate {
    /// 1970-01-01로부터 지난 일수. 그 이전 날짜는 음수다.
    public var epochDay: Int {
        Self.daysFromCivil(year: year, month: month, day: day)
    }

    public init(epochDay: Int) {
        let civil = Self.civilFromDays(epochDay)
        self.init(validatedYear: civil.year, month: civil.month, day: civil.day)
    }

    public func adding(days: Int) -> LocalDate {
        LocalDate(epochDay: epochDay + days)
    }

    /// 월을 더한다. 대상 월에 같은 날이 없으면 그 달의 말일로 맞춘다(1월 31일 + 1개월 = 2월 28/29일).
    public func adding(months: Int) -> LocalDate {
        let first = LocalDate(firstDayOfMonthIndex: monthIndex + months)
        return LocalDate(validatedYear: first.year, month: first.month, day: min(day, first.numberOfDaysInMonth))
    }

    /// `other`까지의 일수. `other`가 더 나중이면 양수.
    public func days(until other: LocalDate) -> Int {
        other.epochDay - epochDay
    }

    // Howard Hinnant, "chrono-Compatible Low-Level Date Algorithms"의 days_from_civil / civil_from_days.
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = (month + 9) % 12 // 3월 = 0
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }
}

// MARK: - Comparable / Strideable

extension LocalDate: Strideable {
    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public func distance(to other: LocalDate) -> Int {
        days(until: other)
    }

    public func advanced(by n: Int) -> LocalDate {
        adding(days: n)
    }
}

// MARK: - 정수 키 (yyyymmdd)

extension LocalDate {
    /// SwiftData/CloudKit에 저장하고 정렬·검색하기 쉬운 정수 표현. 예: 20261019
    public var yyyymmdd: Int {
        year * 10_000 + month * 100 + day
    }

    public init?(yyyymmdd value: Int) {
        guard value > 0 else { return nil }
        self.init(year: value / 10_000, month: (value / 100) % 100, day: value % 100)
    }
}

// MARK: - ISO 8601 문자열 (yyyy-MM-dd)

extension LocalDate: CustomStringConvertible {
    /// "2026-10-19"
    public var iso8601: String {
        "\(Self.zeroPadded(year, width: 4))-\(Self.zeroPadded(month, width: 2))-\(Self.zeroPadded(day, width: 2))"
    }

    public var description: String { iso8601 }

    /// "yyyy-MM-dd" 형식만 받는다.
    public init?(iso8601 text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.utf8.allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    private static func zeroPadded(_ value: Int, width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}

extension LocalDate: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = LocalDate(iso8601: text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a yyyy-MM-dd date, got \(text)"
            )
        }
        self = date
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso8601)
    }
}

// MARK: - Date 변환

extension LocalDate {
    /// `date`가 `timeZone`에서 가리키는 날짜.
    public init(_ date: Date, in timeZone: TimeZone = .current) {
        let components = Self.gregorian(in: timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(validatedYear: components.year!, month: components.month!, day: components.day!)
    }

    /// 이 날짜의 `hour:minute`(`timeZone` 기준) 시각.
    public func date(hour: Int = 0, minute: Int = 0, in timeZone: TimeZone = .current) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return Self.gregorian(in: timeZone).date(from: components)!
    }

    public static func today(in timeZone: TimeZone = .current, now: Date = Date()) -> LocalDate {
        LocalDate(now, in: timeZone)
    }

    static func gregorian(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
