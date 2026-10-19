import Foundation
import Testing
@testable import DayGridCore

private func date(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
    LocalDate(year: year, month: month, day: day)!
}

@Suite("LocalDate 생성과 검증")
struct LocalDateValidationTests {
    @Test func acceptsValidDates() {
        #expect(LocalDate(year: 2026, month: 10, day: 19) != nil)
        #expect(LocalDate(year: 2024, month: 2, day: 29) != nil)
        #expect(LocalDate(year: 2000, month: 2, day: 29) != nil)
    }

    @Test(arguments: [
        [2026, 2, 29], [1900, 2, 29], [2026, 4, 31], [2026, 13, 1], [2026, 0, 1], [2026, 1, 0], [2026, 1, 32],
    ])
    func rejectsInvalidDates(components: [Int]) {
        #expect(LocalDate(year: components[0], month: components[1], day: components[2]) == nil)
    }

    @Test func numberOfDaysInMonth() {
        #expect(date(2026, 2, 1).numberOfDaysInMonth == 28)
        #expect(date(2024, 2, 1).numberOfDaysInMonth == 29)
        #expect(date(2026, 9, 1).numberOfDaysInMonth == 30)
        #expect(date(2026, 12, 1).numberOfDaysInMonth == 31)
    }

    @Test func monthIndexRoundTrip() {
        #expect(date(2026, 10, 19).monthIndex == 2026 * 12 + 9)
        #expect(LocalDate(firstDayOfMonthIndex: date(2026, 10, 19).monthIndex) == date(2026, 10, 1))
        #expect(LocalDate(firstDayOfMonthIndex: date(2026, 1, 31).monthIndex - 1) == date(2025, 12, 1))
        #expect(LocalDate(firstDayOfMonthIndex: date(2026, 12, 5).monthIndex + 1) == date(2027, 1, 1))
    }

    @Test func firstAndLastDayOfMonth() {
        #expect(date(2026, 10, 19).firstDayOfMonth == date(2026, 10, 1))
        #expect(date(2026, 10, 19).lastDayOfMonth == date(2026, 10, 31))
        #expect(date(2024, 2, 10).lastDayOfMonth == date(2024, 2, 29))
    }
}

@Suite("LocalDate 산술")
struct LocalDateArithmeticTests {
    @Test func epochDayRoundTrip() {
        #expect(date(1970, 1, 1).epochDay == 0)
        #expect(date(1969, 12, 31).epochDay == -1)
        #expect(date(2000, 3, 1).epochDay == 11_017)
        for epochDay in stride(from: -800_000, through: 800_000, by: 997) {
            #expect(LocalDate(epochDay: epochDay).epochDay == epochDay)
        }
    }

    @Test func weekday() {
        #expect(date(1970, 1, 1).weekday == 5) // 목
        #expect(date(2000, 1, 1).weekday == 7) // 토
        #expect(date(2026, 10, 18).weekday == 1) // 일
        #expect(date(2026, 10, 19).weekday == 2) // 월
        #expect(date(1969, 12, 28).weekday == 1) // 일 (epoch 이전)
    }

    @Test func addingDaysAcrossBoundaries() {
        #expect(date(2026, 10, 31).adding(days: 1) == date(2026, 11, 1))
        #expect(date(2026, 12, 31).adding(days: 1) == date(2027, 1, 1))
        #expect(date(2024, 2, 28).adding(days: 1) == date(2024, 2, 29))
        #expect(date(2026, 2, 28).adding(days: 1) == date(2026, 3, 1))
        #expect(date(2026, 1, 1).adding(days: -1) == date(2025, 12, 31))
        #expect(date(2026, 1, 1).adding(days: 365) == date(2027, 1, 1))
    }

    @Test func addingMonthsClampsToLastDay() {
        #expect(date(2026, 1, 31).adding(months: 1) == date(2026, 2, 28))
        #expect(date(2024, 1, 31).adding(months: 1) == date(2024, 2, 29))
        #expect(date(2026, 3, 31).adding(months: -1) == date(2026, 2, 28))
        #expect(date(2026, 12, 15).adding(months: 1) == date(2027, 1, 15))
        #expect(date(2026, 1, 15).adding(months: -1) == date(2025, 12, 15))
        #expect(date(2026, 1, 15).adding(months: -13) == date(2024, 12, 15))
        #expect(date(2026, 10, 19).adding(months: 24) == date(2028, 10, 19))
    }

    @Test func daysUntil() {
        #expect(date(2026, 10, 19).days(until: date(2026, 10, 25)) == 6)
        #expect(date(2026, 10, 25).days(until: date(2026, 10, 19)) == -6)
        #expect(date(2026, 1, 1).days(until: date(2027, 1, 1)) == 365)
        #expect(date(2028, 1, 1).days(until: date(2029, 1, 1)) == 366)
    }

    @Test func comparisonAndRanges() {
        #expect(date(2026, 10, 19) < date(2026, 10, 20))
        #expect(date(2026, 9, 30) < date(2026, 10, 1))
        #expect(date(2025, 12, 31) < date(2026, 1, 1))
        let october = date(2026, 10, 1)...date(2026, 10, 31)
        #expect(october.count == 31)
        #expect(october.contains(date(2026, 10, 19)))
        #expect(!october.contains(date(2026, 11, 1)))
    }
}

@Suite("LocalDate 변환")
struct LocalDateConversionTests {
    @Test func yyyymmddRoundTrip() {
        #expect(date(2026, 10, 19).yyyymmdd == 20_261_019)
        #expect(LocalDate(yyyymmdd: 20_261_019) == date(2026, 10, 19))
        #expect(LocalDate(yyyymmdd: 20_260_229) == nil)
        #expect(LocalDate(yyyymmdd: 0) == nil)
    }

    @Test func iso8601() {
        #expect(date(2026, 1, 5).iso8601 == "2026-01-05")
        #expect(date(2026, 10, 19).description == "2026-10-19")
        #expect(LocalDate(iso8601: "2026-10-19") == date(2026, 10, 19))
    }

    @Test(arguments: ["", "2026-10", "2026-1-19", "2026-10-19T00:00", "2026-02-30", "20261019", "+026-10-19", "２０２６-10-19"])
    func iso8601RejectsMalformedText(text: String) {
        #expect(LocalDate(iso8601: text) == nil)
    }

    @Test func codableUsesISOString() throws {
        let encoded = try JSONEncoder().encode([date(2026, 10, 19)])
        #expect(String(decoding: encoded, as: UTF8.self) == #"["2026-10-19"]"#)
        let decoded = try JSONDecoder().decode([LocalDate].self, from: encoded)
        #expect(decoded == [date(2026, 10, 19)])
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([LocalDate].self, from: Data(#"["2026-13-01"]"#.utf8))
        }
    }

    @Test func dateConversionRespectsTimeZone() {
        let seoul = TimeZone(secondsFromGMT: 9 * 3600)!
        let utc = TimeZone(secondsFromGMT: 0)!
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = utc
        // 2026-10-18 15:30 UTC = 2026-10-19 00:30 서울
        let instant = utcCalendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 15, minute: 30))!

        #expect(LocalDate(instant, in: utc) == date(2026, 10, 18))
        #expect(LocalDate(instant, in: seoul) == date(2026, 10, 19))
        #expect(LocalDate.today(in: seoul, now: instant) == date(2026, 10, 19))
    }

    @Test func dateAtTimeOfDay() {
        let seoul = TimeZone(secondsFromGMT: 9 * 3600)!
        let nineAM = date(2026, 10, 19).date(hour: 9, minute: 30, in: seoul)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: nineAM)
        #expect([c.year, c.month, c.day, c.hour, c.minute] == [2026, 10, 19, 0, 30])
        #expect(LocalDate(nineAM, in: seoul) == date(2026, 10, 19))
    }
}

@Suite("LocalDate 한국어 표기")
struct LocalDateKoreanTests {
    @Test func koreanText() {
        #expect(date(2026, 10, 19).koreanWeekdaySymbol == "월")
        #expect(date(2026, 10, 18).koreanWeekdaySymbol == "일")
        #expect(date(2026, 10, 24).koreanWeekdaySymbol == "토")
        #expect(date(2026, 10, 19).koreanMonthTitle == "2026년 10월")
        #expect(date(2026, 1, 5).koreanLongText == "2026년 1월 5일 (월)")
        #expect(date(2026, 10, 28).koreanMonthDayText == "10월 28일")
        #expect(date(2026, 10, 19).koreanMonthDayWeekdayText == "10월 19일 (월)")
    }
}
