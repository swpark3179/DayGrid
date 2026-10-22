/// 날짜 칸에 붙는 표시: 공휴일 이름(숫자를 빨갛게), 개인 휴일 이름(주황), 생일인 사람.
/// 반복 할일은 달력에 보이지 않는다(사용자 결정 2026-10-22).
public struct DayMark: Hashable, Sendable {
    /// 공휴일 이름(같은 이름은 한 번만).
    public var holidayNames: [String] = []
    /// 개인 휴일 이름(같은 이름은 한 번만). 공휴일과 다른 색으로 그린다.
    public var personalHolidayNames: [String] = []
    public var birthdayNames: [String] = []

    public init(
        holidayNames: [String] = [],
        personalHolidayNames: [String] = [],
        birthdayNames: [String] = []
    ) {
        self.holidayNames = holidayNames
        self.personalHolidayNames = personalHolidayNames
        self.birthdayNames = birthdayNames
    }

    public var isPublicHoliday: Bool { !holidayNames.isEmpty }

    /// 공휴일이 아닌 개인 휴일. 공휴일과 겹치면 공휴일로 본다.
    public var isPersonalHoliday: Bool { holidayNames.isEmpty && !personalHolidayNames.isEmpty }

    /// 달력 칸의 날짜 옆에 붙일 짧은 글자. 공휴일 이름을 먼저 쓴다. 예: "추석", "🎂", "🎂개천절"
    public var calendarLabel: String? {
        let name = holidayNames.first ?? personalHolidayNames.first ?? ""
        let text = (birthdayNames.isEmpty ? "" : "🎂") + name
        return text.isEmpty ? nil : text
    }

    /// 접근성용 설명. 예: "개천절, 김민수 생일"
    public var spokenDescription: String? {
        let parts = holidayNames + personalHolidayNames + birthdayNames.map { "\($0) 생일" }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// `range` 안의 날짜별 표시를 모은다.
public enum DayMarks {
    public static func make(
        in range: ClosedRange<LocalDate>,
        holidays: [Holiday],
        personalHolidays: [(name: String, start: LocalDate, end: LocalDate)],
        birthdays: [(name: String, birthday: Birthday)]
    ) -> [LocalDate: DayMark] {
        var marks: [LocalDate: DayMark] = [:]

        for holiday in holidays where range.contains(holiday.date) {
            if !(marks[holiday.date]?.holidayNames.contains(holiday.name) ?? false) {
                marks[holiday.date, default: DayMark()].holidayNames.append(holiday.name)
            }
        }
        for personal in personalHolidays {
            let start = max(personal.start, range.lowerBound)
            let end = min(max(personal.start, personal.end), range.upperBound)
            guard start <= end else { continue }
            for date in start...end where !(marks[date]?.personalHolidayNames.contains(personal.name) ?? false) {
                marks[date, default: DayMark()].personalHolidayNames.append(personal.name)
            }
        }
        for person in birthdays {
            for date in person.birthday.occurrences(in: range) {
                marks[date, default: DayMark()].birthdayNames.append(person.name)
            }
        }
        return marks
    }
}
