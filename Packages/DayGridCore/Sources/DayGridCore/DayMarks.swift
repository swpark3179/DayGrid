/// 날짜 칸에 붙는 표시: 공휴일 이름(숫자를 빨갛게), 개인 휴일 이름(주황), 생일인 사람, 그날 완료한 반복 할일 수.
public struct DayMark: Hashable, Sendable {
    /// 공휴일 이름(같은 이름은 한 번만).
    public var holidayNames: [String] = []
    /// 개인 휴일 이름(같은 이름은 한 번만). 공휴일과 다른 색으로 그린다.
    public var personalHolidayNames: [String] = []
    public var birthdayNames: [String] = []
    /// 이 날 체크한 반복 할일 수
    public var completedRecurringCount = 0

    public init(
        holidayNames: [String] = [],
        personalHolidayNames: [String] = [],
        birthdayNames: [String] = [],
        completedRecurringCount: Int = 0
    ) {
        self.holidayNames = holidayNames
        self.personalHolidayNames = personalHolidayNames
        self.birthdayNames = birthdayNames
        self.completedRecurringCount = completedRecurringCount
    }

    public var isPublicHoliday: Bool { !holidayNames.isEmpty }

    /// 공휴일이 아닌 개인 휴일. 공휴일과 겹치면 공휴일로 본다.
    public var isPersonalHoliday: Bool { holidayNames.isEmpty && !personalHolidayNames.isEmpty }

    /// 달력 칸의 날짜 옆에 붙일 짧은 글자. 공휴일 이름을 먼저 쓴다. 예: "추석", "🎂", "✓", "🎂✓개천절"
    public var calendarLabel: String? {
        let name = holidayNames.first ?? personalHolidayNames.first ?? ""
        let text = (birthdayNames.isEmpty ? "" : "🎂") + (completedRecurringCount > 0 ? "✓" : "") + name
        return text.isEmpty ? nil : text
    }

    /// 접근성용 설명. 예: "개천절, 김민수 생일, 반복 할일 2개 완료"
    public var spokenDescription: String? {
        var parts = holidayNames + personalHolidayNames + birthdayNames.map { "\($0) 생일" }
        if completedRecurringCount > 0 {
            parts.append("반복 할일 \(completedRecurringCount)개 완료")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// `range` 안의 날짜별 표시를 모은다.
public enum DayMarks {
    public static func make(
        in range: ClosedRange<LocalDate>,
        holidays: [Holiday],
        personalHolidays: [(name: String, start: LocalDate, end: LocalDate)],
        birthdays: [(name: String, birthday: Birthday)],
        recurringCompletions: [LocalDate] = []
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
        for date in recurringCompletions where range.contains(date) {
            marks[date, default: DayMark()].completedRecurringCount += 1
        }
        return marks
    }
}
