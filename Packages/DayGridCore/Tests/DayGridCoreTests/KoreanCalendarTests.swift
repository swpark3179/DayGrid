import Foundation
import Testing
@testable import DayGridCore

private func day(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
    LocalDate(year: year, month: month, day: day)!
}

// 기대값은 korean_lunar_calendar(한국천문연구원 기준)로 구했다.
// scripts/make_lunar_table.py로 만든 표는 1900–2050년 모든 날을 양방향으로 대조해 같았다.
@Suite("KoreanLunarCalendar")
struct KoreanLunarCalendarTests {
    @Test func seollalFollowsTheKoreanCalendar() {
        let expected = [
            2025: day(2025, 1, 29), 2026: day(2026, 2, 17), 2027: day(2027, 2, 7),
            2028: day(2028, 1, 27), 2029: day(2029, 2, 13), 2030: day(2030, 2, 3),
        ]
        for (year, seollal) in expected {
            #expect(KoreanLunarCalendar.solarDate(year: year, month: 1, day: 1) == seollal, "\(year)년 설날")
        }
    }

    @Test func lunarToSolar() {
        #expect(KoreanLunarCalendar.solarDate(year: 2026, month: 8, day: 15) == day(2026, 9, 25))
        #expect(KoreanLunarCalendar.solarDate(year: 2026, month: 4, day: 8) == day(2026, 5, 24))
        #expect(KoreanLunarCalendar.solarDate(year: 2026, month: 9, day: 10) == day(2026, 10, 20))
        #expect(KoreanLunarCalendar.solarDate(year: 1900, month: 1, day: 1) == day(1900, 1, 31))
        #expect(KoreanLunarCalendar.solarDate(year: 2049, month: 12, day: 29) == day(2050, 1, 22))
    }

    @Test func leapMonths() {
        #expect(KoreanLunarCalendar.leapMonth(inYear: 2025) == 6)
        #expect(KoreanLunarCalendar.leapMonth(inYear: 2026) == nil)
        #expect(KoreanLunarCalendar.solarDate(year: 2025, month: 6, day: 1) == day(2025, 6, 25))
        #expect(KoreanLunarCalendar.solarDate(year: 2025, month: 6, day: 1, isLeapMonth: true) == day(2025, 7, 25))
        #expect(KoreanLunarCalendar.solarDate(year: 2025, month: 6, day: 29, isLeapMonth: true) == day(2025, 8, 22))
    }

    @Test func missingDatesAreNil() {
        #expect(KoreanLunarCalendar.solarDate(year: 2025, month: 6, day: 30, isLeapMonth: true) == nil)
        #expect(KoreanLunarCalendar.solarDate(year: 2025, month: 12, day: 30) == nil)
        #expect(KoreanLunarCalendar.solarDate(year: 2026, month: 5, day: 1, isLeapMonth: true) == nil)
        #expect(KoreanLunarCalendar.solarDate(year: 2026, month: 13, day: 1) == nil)
        #expect(KoreanLunarCalendar.solarDate(year: 1899, month: 1, day: 1) == nil)
        #expect(KoreanLunarCalendar.solarDate(year: 2050, month: 1, day: 1) == nil)
    }

    @Test func monthLengths() {
        let lengths = (1...12).compactMap { KoreanLunarCalendar.numberOfDays(year: 2026, month: $0) }
        #expect(lengths == [30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 30])
    }

    @Test func solarToLunar() {
        #expect(KoreanLunarCalendar.lunarDate(from: day(2026, 10, 19)) == LunarDate(year: 2026, month: 9, day: 9))
        #expect(KoreanLunarCalendar.lunarDate(from: day(2025, 7, 25)) == LunarDate(year: 2025, month: 6, day: 1, isLeapMonth: true))
        #expect(KoreanLunarCalendar.lunarDate(from: day(2027, 2, 6)) == LunarDate(year: 2026, month: 12, day: 30))
        #expect(KoreanLunarCalendar.lunarDate(from: day(1900, 1, 30)) == nil)
        #expect(KoreanLunarCalendar.lunarDate(from: day(2050, 1, 23)) == nil)
    }

    @Test func roundTripsEveryDayOfAYear() {
        var date = day(2025, 1, 1)
        while date <= day(2026, 12, 31) {
            let lunar = KoreanLunarCalendar.lunarDate(from: date)
            #expect(lunar.flatMap { KoreanLunarCalendar.solarDate($0) } == date, "\(date)")
            date = date.adding(days: 1)
        }
    }
}

@Suite("Birthday")
struct BirthdayTests {
    @Test func leapDayBirthdayIsFebruary28thInCommonYears() {
        let birthday = Birthday(month: 2, day: 29)
        #expect(birthday.date(inYear: 2026) == day(2026, 2, 28))
        #expect(birthday.date(inYear: 2028) == day(2028, 2, 29))
    }

    @Test func lunarBirthdayNextOccurrence() {
        let birthday = Birthday(month: 9, day: 10, isLunar: true)
        #expect(birthday.nextOccurrence(onOrAfter: day(2026, 10, 19)) == day(2026, 10, 20))
        #expect(birthday.nextOccurrence(onOrAfter: day(2026, 10, 20)) == day(2026, 10, 20))
    }

    @Test func lateLunarMonthsFallInTheNextSolarYear() {
        let birthday = Birthday(month: 12, day: 20, isLunar: true)
        #expect(birthday.nextOccurrence(onOrAfter: day(2026, 10, 19)) == day(2027, 1, 27))
        #expect(birthday.occurrences(in: day(2026, 1, 1)...day(2026, 12, 31)) == [day(2026, 2, 7)])
    }

    @Test func leapMonthBirthdayUsesTheRegularMonthWithoutALeapMonth() {
        let birthday = Birthday(month: 6, day: 1, isLunar: true, isLeapMonth: true)
        #expect(birthday.date(inYear: 2025) == day(2025, 7, 25))
        #expect(birthday.date(inYear: 2026) == day(2026, 7, 14))
    }

    @Test func thirtiethInAShortMonthIsTheTwentyNinth() {
        let birthday = Birthday(month: 2, day: 30, isLunar: true)
        #expect(birthday.date(inYear: 2026) == day(2026, 4, 16))
    }

    @Test func solarBirthdaysIgnoreTheLeapFlag() {
        #expect(!Birthday(month: 6, day: 1, isLeapMonth: true).isLeapMonth)
    }

    @Test func koreanText() {
        #expect(Birthday(month: 10, day: 19).koreanText == "10월 19일")
        #expect(Birthday(month: 8, day: 15, isLunar: true).koreanText == "음력 8월 15일")
        #expect(Birthday(month: 6, day: 3, isLunar: true, isLeapMonth: true).koreanText == "음력 윤6월 3일")
    }

    @Test func upcomingWithinThirtyDays() {
        let today = day(2026, 10, 19)
        let list = UpcomingBirthday.list(
            [
                (id: "A", birthday: Birthday(month: 10, day: 22)),
                (id: "B", birthday: Birthday(month: 9, day: 10, isLunar: true)),
                (id: "C", birthday: Birthday(month: 11, day: 30)),
                (id: "D", birthday: Birthday(month: 10, day: 19)),
            ],
            today: today
        )
        #expect(list.map { $0.id } == ["D", "B", "A"])
        #expect(list.map { $0.daysLeft } == [0, 1, 3])
        #expect(list.map { $0.koreanDDay } == ["오늘", "D-1", "D-3"])
    }
}

@Suite("KoreanHolidays")
struct KoreanHolidaysTests {
    private func summary(_ year: Int, overrides: HolidayOverrides = .empty) -> [String] {
        KoreanHolidays.holidays(inYear: year, overrides: overrides).map { "\($0.date.month)/\($0.date.day) \($0.name)" }
    }

    @Test func year2026() {
        #expect(summary(2026) == [
            "1/1 신정", "2/16 설날", "2/17 설날", "2/18 설날", "3/1 삼일절", "3/2 대체공휴일",
            "5/5 어린이날", "5/24 부처님오신날", "5/25 대체공휴일", "6/6 현충일", "8/15 광복절", "8/17 대체공휴일",
            "9/24 추석", "9/25 추석", "9/26 추석", "10/3 개천절", "10/5 대체공휴일", "10/9 한글날", "12/25 기독탄신일",
        ])
    }

    @Test func year2027UsesTheKoreanSeollal() {
        #expect(summary(2027) == [
            "1/1 신정", "2/6 설날", "2/7 설날", "2/8 설날", "2/9 대체공휴일", "3/1 삼일절",
            "5/5 어린이날", "5/13 부처님오신날", "6/6 현충일", "8/15 광복절", "8/16 대체공휴일",
            "9/14 추석", "9/15 추석", "9/16 추석", "10/3 개천절", "10/4 대체공휴일", "10/9 한글날", "10/11 대체공휴일",
            "12/25 기독탄신일", "12/27 대체공휴일",
        ])
    }

    @Test func twoHolidaysOnOneDayGiveOneSubstitute() {
        // 2025년 5월 5일은 어린이날과 부처님오신날이 겹친다.
        #expect(summary(2025) == [
            "1/1 신정", "1/28 설날", "1/29 설날", "1/30 설날", "3/1 삼일절", "3/3 대체공휴일",
            "5/5 부처님오신날", "5/5 어린이날", "5/6 대체공휴일", "6/6 현충일", "8/15 광복절",
            "10/3 개천절", "10/5 추석", "10/6 추석", "10/7 추석", "10/8 대체공휴일", "10/9 한글날", "12/25 기독탄신일",
        ])
        // 2028년 추석 연휴가 개천절과 겹친다.
        #expect(summary(2028).filter { $0.hasPrefix("10/") } == [
            "10/2 추석", "10/3 개천절", "10/3 추석", "10/4 추석", "10/5 대체공휴일", "10/9 한글날",
        ])
    }

    @Test func substituteRulesStartInTheirYear() {
        // 2023년부터 부처님오신날도 대체공휴일이 생긴다(5/27 토요일 → 5/29).
        #expect(summary(2023).contains("5/29 대체공휴일"))
        // 2020년 광복절(토요일)은 대체공휴일이 없었다.
        #expect(!summary(2020).contains("8/17 대체공휴일"))
        // 2024년 설날 연휴(금–일)는 일요일과 겹쳐 월요일이 대체공휴일이다.
        #expect(summary(2024).contains("2/12 대체공휴일"))
    }

    @Test func overridesAddAndRemove() throws {
        let json = """
            {"version": 3, "added": [{"date": "2025-01-27", "name": "임시공휴일"}, {"date": "2025-06-03", "name": "대통령 선거일"}],
             "removed": ["2025-03-03"]}
            """
        let overrides = try JSONDecoder().decode(HolidayOverrides.self, from: Data(json.utf8))
        #expect(overrides.version == 3)
        let names = summary(2025, overrides: overrides)
        #expect(names.contains("1/27 임시공휴일"))
        #expect(names.contains("6/3 대통령 선거일"))
        #expect(!names.contains("3/3 대체공휴일"))
        #expect(!summary(2026, overrides: overrides).contains("1/27 임시공휴일"))
    }

    @Test func holidaysInARangeCrossYears() {
        let range = day(2026, 12, 20)...day(2027, 1, 5)
        #expect(KoreanHolidays.holidays(in: range).map { $0.name } == ["기독탄신일", "신정"])
    }
}

@Suite("DayMarks")
struct DayMarksTests {
    @Test func collectsHolidaysPersonalDaysAndBirthdays() {
        let range = day(2026, 10, 1)...day(2026, 10, 31)
        let marks = DayMarks.make(
            in: range,
            holidays: KoreanHolidays.holidays(in: range),
            personalHolidays: [
                (name: "회사 휴무", start: day(2026, 10, 16), end: day(2026, 10, 16)),
                (name: "가을 휴가", start: day(2026, 9, 29), end: day(2026, 10, 2)),
            ],
            birthdays: [
                (name: "김민수", birthday: Birthday(month: 10, day: 3)),
                (name: "엄마", birthday: Birthday(month: 9, day: 10, isLunar: true)),
            ]
        )
        #expect(marks[day(2026, 10, 3)] == DayMark(holidayNames: ["개천절"], birthdayNames: ["김민수"]))
        #expect(marks[day(2026, 10, 3)]?.calendarLabel == "🎂개천절")
        #expect(marks[day(2026, 10, 3)]?.spokenDescription == "개천절, 김민수 생일")
        #expect(marks[day(2026, 10, 5)]?.holidayNames == ["대체공휴일"])
        #expect(marks[day(2026, 10, 3)]?.isPublicHoliday == true)
        #expect(marks[day(2026, 10, 16)] == DayMark(personalHolidayNames: ["회사 휴무"]))
        #expect(marks[day(2026, 10, 16)]?.isPersonalHoliday == true)
        #expect(marks[day(2026, 10, 16)]?.isPublicHoliday == false)
        #expect(marks[day(2026, 10, 16)]?.calendarLabel == "회사 휴무")
        #expect(marks[day(2026, 10, 16)]?.spokenDescription == "회사 휴무")
        #expect(marks[day(2026, 10, 20)] == DayMark(birthdayNames: ["엄마"]))
        #expect(marks[day(2026, 10, 20)]?.calendarLabel == "🎂")
        #expect(marks[day(2026, 10, 2)]?.personalHolidayNames == ["가을 휴가"])
        #expect(marks[day(2026, 10, 2)]?.holidayNames == [])
        #expect(marks[day(2026, 9, 30)] == nil, "범위 밖은 넣지 않는다")
        #expect(marks[day(2026, 10, 19)] == nil)
        #expect(marks.keys.sorted().map { $0.day } == [1, 2, 3, 5, 9, 16, 20])
    }
}

@Suite("DayMarks 공휴일과 개인 휴일")
struct DayMarksPersonalHolidayTests {
    @Test func aPublicHolidayWinsOverAPersonalHolidayOnTheSameDay() {
        let range = day(2026, 10, 1)...day(2026, 10, 31)
        let marks = DayMarks.make(
            in: range,
            holidays: KoreanHolidays.holidays(in: range),
            personalHolidays: [(name: "연차", start: day(2026, 10, 9), end: day(2026, 10, 9))],
            birthdays: []
        )
        let hangul = marks[day(2026, 10, 9)]
        #expect(hangul?.holidayNames == ["한글날"])
        #expect(hangul?.personalHolidayNames == ["연차"])
        #expect(hangul?.isPublicHoliday == true)
        #expect(hangul?.isPersonalHoliday == false)
        #expect(hangul?.calendarLabel == "한글날")
        #expect(hangul?.spokenDescription == "한글날, 연차")
    }
}
