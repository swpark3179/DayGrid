/// 날짜 칸에 붙는 표시: 공휴일·개인 휴일 이름(숫자를 빨갛게)과 생일인 사람.
public struct DayMark: Hashable, Sendable {
    /// 공휴일과 개인 휴일 이름(같은 이름은 한 번만).
    public var holidayNames: [String] = []
    public var birthdayNames: [String] = []

    public init(holidayNames: [String] = [], birthdayNames: [String] = []) {
        self.holidayNames = holidayNames
        self.birthdayNames = birthdayNames
    }

    public var isHoliday: Bool { !holidayNames.isEmpty }

    /// 달력 칸의 날짜 옆에 붙일 짧은 글자. 예: "추석", "🎂", "🎂개천절"
    public var calendarLabel: String? {
        let text = (birthdayNames.isEmpty ? "" : "🎂") + (holidayNames.first ?? "")
        return text.isEmpty ? nil : text
    }

    /// 접근성용 설명. 예: "개천절, 김민수 생일"
    public var spokenDescription: String? {
        let parts = holidayNames + birthdayNames.map { "\($0) 생일" }
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

        func addHoliday(_ name: String, on date: LocalDate) {
            guard range.contains(date), !(marks[date]?.holidayNames.contains(name) ?? false) else { return }
            marks[date, default: DayMark()].holidayNames.append(name)
        }

        for holiday in holidays {
            addHoliday(holiday.name, on: holiday.date)
        }
        for personal in personalHolidays {
            let start = max(personal.start, range.lowerBound)
            let end = min(max(personal.start, personal.end), range.upperBound)
            guard start <= end else { continue }
            for date in start...end {
                addHoliday(personal.name, on: date)
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
