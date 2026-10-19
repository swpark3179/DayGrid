import Foundation
import Testing
@testable import DayGridCore

private func day(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
    LocalDate(year: year, month: month, day: day)!
}

private let seoul = TimeZone(secondsFromGMT: 9 * 3600)!

@Suite("ScheduleHint")
struct ScheduleHintTests {
    @Test func defaultIsOneAllDay() {
        let hint = ScheduleHint()
        #expect(hint.isAllDay)
        #expect(hint.dayCount == 1)
        #expect(hint.startMinute == 9 * 60)
        #expect(hint.durationMinutes == 60)
        #expect(hint.endDay(startingOn: day(2026, 10, 19)) == day(2026, 10, 19))
    }

    @Test func clampsOutOfRangeValues() {
        let low = ScheduleHint(isAllDay: false, dayCount: 0, startMinute: -5, durationMinutes: -10)
        #expect(low.dayCount == 1)
        #expect(low.startMinute == 0)
        #expect(low.durationMinutes == 0)
        let high = ScheduleHint(isAllDay: false, startMinute: 2000)
        #expect(high.startMinute == 24 * 60 - 1)
    }

    @Test func allDayKeepsTheNumberOfDays() {
        let hint = ScheduleHint.allDay(from: day(2026, 10, 28), through: day(2026, 11, 3))
        #expect(hint.isAllDay)
        #expect(hint.dayCount == 7)
        #expect(hint.endDay(startingOn: day(2026, 11, 10)) == day(2026, 11, 16))

        let reversed = ScheduleHint.allDay(from: day(2026, 10, 28), through: day(2026, 10, 20))
        #expect(reversed.dayCount == 1)
    }

    @Test func timedKeepsStartTimeAndLength() {
        let start = day(2026, 10, 5).date(hour: 14, in: seoul)
        let end = day(2026, 10, 5).date(hour: 15, minute: 30, in: seoul)
        let hint = ScheduleHint.timed(start: start, end: end, timeZone: seoul)
        #expect(!hint.isAllDay)
        #expect(hint.startMinute == 14 * 60)
        #expect(hint.durationMinutes == 90)
        #expect(hint.startDate(on: day(2026, 10, 21), in: seoul) == day(2026, 10, 21).date(hour: 14, in: seoul))
        #expect(hint.endDate(on: day(2026, 10, 21), in: seoul) == day(2026, 10, 21).date(hour: 15, minute: 30, in: seoul))
    }

    @Test func timedAcrossMidnightEndsTheNextDay() {
        let start = day(2026, 10, 5).date(hour: 22, in: seoul)
        let end = day(2026, 10, 6).date(hour: 1, in: seoul)
        let hint = ScheduleHint.timed(start: start, end: end, timeZone: seoul)
        #expect(hint.startMinute == 22 * 60)
        #expect(hint.durationMinutes == 180)
        #expect(hint.endDate(on: day(2026, 12, 31), in: seoul) == day(2027, 1, 1).date(hour: 1, in: seoul))
    }

    @Test func startMinuteDependsOnTheTimeZone() {
        let start = day(2026, 10, 5).date(hour: 14, in: seoul)
        let utc = TimeZone(secondsFromGMT: 0)!
        #expect(ScheduleHint.timed(start: start, end: start, timeZone: utc).startMinute == 5 * 60)
        #expect(LocalDate.minuteOfDay(start, in: seoul) == 14 * 60)
    }
}

@Suite("QuickDay")
struct QuickDayTests {
    @Test func fromAWeekday() {
        let monday = day(2026, 10, 19)
        #expect(QuickDay.today.date(from: monday) == monday)
        #expect(QuickDay.tomorrow.date(from: monday) == day(2026, 10, 20))
        #expect(QuickDay.weekend.date(from: monday) == day(2026, 10, 24))
        #expect(QuickDay.weekend.date(from: day(2026, 10, 23)) == day(2026, 10, 24))
    }

    @Test func onTheWeekendItIsToday() {
        #expect(QuickDay.weekend.date(from: day(2026, 10, 24)) == day(2026, 10, 24))
        #expect(QuickDay.weekend.date(from: day(2026, 10, 25)) == day(2026, 10, 25))
    }

    @Test func acrossTheYearEnd() {
        let newYearsEve = day(2026, 12, 31)
        #expect(QuickDay.tomorrow.date(from: newYearsEve) == day(2027, 1, 1))
        #expect(QuickDay.weekend.date(from: newYearsEve) == day(2027, 1, 2))
    }

    @Test func koreanTitles() {
        #expect(QuickDay.allCases.map { $0.koreanTitle } == ["오늘", "내일", "이번 주말"])
    }
}
