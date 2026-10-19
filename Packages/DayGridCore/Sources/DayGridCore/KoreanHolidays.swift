/// 공휴일 하루.
public struct Holiday: Hashable, Sendable, Codable {
    public let date: LocalDate
    public let name: String

    public init(date: LocalDate, name: String) {
        self.date = date
        self.name = name
    }
}

/// 계산으로 구할 수 없는 공휴일(선거일, 임시공휴일)과, 계산 결과에서 뺄 날짜.
/// 저장소의 `KR-overrides.json`을 앱에 넣고, 앱이 가끔 새 버전을 받아 온다.
public struct HolidayOverrides: Hashable, Sendable, Codable {
    public var version: Int
    public var added: [Holiday]
    public var removed: [LocalDate]

    public init(version: Int = 0, added: [Holiday] = [], removed: [LocalDate] = []) {
        self.version = version
        self.added = added
        self.removed = removed
    }

    public static let empty = HolidayOverrides()
}

/// 대한민국 공휴일 계산(「관공서의 공휴일에 관한 규정」).
///
/// - 양력: 1/1, 3/1, 5/5, 6/6, 8/15, 10/3, 10/9, 12/25
/// - 음력: 설날(전날·당일·다음 날), 부처님오신날(4/8), 추석(전날·당일·다음 날)
/// - 대체공휴일
///   - 설날·추석 연휴가 일요일이나 다른 공휴일과 겹치면 연휴 다음 첫 평일(2014년부터)
///   - 어린이날이 토·일요일이나 다른 공휴일과 겹치면 다음 첫 평일(2014년부터)
///   - 삼일절·광복절·개천절·한글날(2021년부터), 부처님오신날·기독탄신일(2023년부터)도 같은 규칙
///   - 한 날에 공휴일이 둘 겹치면 대체공휴일은 하나만 생긴다(예: 2025년 5월 5일).
/// - 선거일과 임시공휴일은 `HolidayOverrides`로 더한다.
public enum KoreanHolidays {
    public static let substituteName = "대체공휴일"

    /// 그 해의 공휴일(날짜순). 음력 표 범위 밖의 해는 양력 공휴일만 계산한다.
    public static func holidays(inYear year: Int, overrides: HolidayOverrides = .empty) -> [Holiday] {
        let groups = baseGroups(inYear: year)
        var holidays = groups.flatMap { group in group.days.map { Holiday(date: $0, name: group.name) } }
        holidays += substitutes(for: groups, year: year)
        holidays += overrides.added.filter { $0.date.year == year }
        let removed = Set(overrides.removed)
        return Array(Set(holidays.filter { !removed.contains($0.date) }))
            .sorted { ($0.date, $0.name) < ($1.date, $1.name) }
    }

    /// `range` 안의 공휴일(날짜순).
    public static func holidays(in range: ClosedRange<LocalDate>, overrides: HolidayOverrides = .empty) -> [Holiday] {
        (range.lowerBound.year...range.upperBound.year)
            .flatMap { holidays(inYear: $0, overrides: overrides) }
            .filter { range.contains($0.date) }
    }

    // MARK: - 기본 공휴일

    private enum SubstituteRule {
        case none
        /// 토·일요일이나 다른 공휴일과 겹치면
        case weekendOrOverlap(since: Int)
        /// 설날·추석 연휴: 일요일이나 다른 공휴일과 겹치면
        case sundayOrOverlap(since: Int)
    }

    private struct Group {
        let name: String
        let days: [LocalDate]
        let rule: SubstituteRule
    }

    private static func baseGroups(inYear year: Int) -> [Group] {
        func solar(_ name: String, _ month: Int, _ day: Int, _ rule: SubstituteRule) -> Group? {
            LocalDate(year: year, month: month, day: day).map { Group(name: name, days: [$0], rule: rule) }
        }
        func lunarHoliday(_ name: String, _ month: Int, _ day: Int, spanning: Bool, _ rule: SubstituteRule) -> Group? {
            guard let date = KoreanLunarCalendar.solarDate(year: year, month: month, day: day) else { return nil }
            let days = spanning ? [date.adding(days: -1), date, date.adding(days: 1)] : [date]
            return Group(name: name, days: days, rule: rule)
        }

        return [
            solar("신정", 1, 1, .none),
            lunarHoliday("설날", 1, 1, spanning: true, .sundayOrOverlap(since: 2014)),
            solar("삼일절", 3, 1, .weekendOrOverlap(since: 2021)),
            solar("어린이날", 5, 5, .weekendOrOverlap(since: 2014)),
            lunarHoliday("부처님오신날", 4, 8, spanning: false, .weekendOrOverlap(since: 2023)),
            solar("현충일", 6, 6, .none),
            solar("광복절", 8, 15, .weekendOrOverlap(since: 2021)),
            lunarHoliday("추석", 8, 15, spanning: true, .sundayOrOverlap(since: 2014)),
            solar("개천절", 10, 3, .weekendOrOverlap(since: 2021)),
            solar("한글날", 10, 9, .weekendOrOverlap(since: 2021)),
            solar("기독탄신일", 12, 25, .weekendOrOverlap(since: 2023)),
        ]
        .compactMap { $0 }
        .sorted { $0.days[0] < $1.days[0] }
    }

    // MARK: - 대체공휴일

    private static func substitutes(for groups: [Group], year: Int) -> [Holiday] {
        var taken = Set(groups.flatMap(\.days))
        var compensatedDays = Set<LocalDate>()
        var result: [Holiday] = []

        for (index, group) in groups.enumerated() {
            let otherDays = Set(groups.enumerated().filter { $0.offset != index }.flatMap { $0.element.days })
            let triggers: [LocalDate]
            switch group.rule {
            case .none:
                continue
            case .weekendOrOverlap(let since):
                guard year >= since else { continue }
                triggers = group.days.filter { isWeekend($0) || otherDays.contains($0) }
            case .sundayOrOverlap(let since):
                guard year >= since else { continue }
                triggers = group.days.filter { $0.weekday == 1 || otherDays.contains($0) }
            }
            // 이미 다른 공휴일의 대체공휴일로 보상한 날이면 다시 만들지 않는다.
            guard !triggers.isEmpty, !triggers.allSatisfy({ compensatedDays.contains($0) }) else { continue }
            compensatedDays.formUnion(triggers)

            var candidate = group.days[group.days.count - 1].adding(days: 1)
            while taken.contains(candidate) || isWeekend(candidate) {
                candidate = candidate.adding(days: 1)
            }
            taken.insert(candidate)
            result.append(Holiday(date: candidate, name: substituteName))
        }
        return result
    }

    private static func isWeekend(_ date: LocalDate) -> Bool {
        date.weekday == 1 || date.weekday == 7
    }
}
