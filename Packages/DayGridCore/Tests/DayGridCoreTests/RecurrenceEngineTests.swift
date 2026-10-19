import Testing
@testable import DayGridCore

private func day(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
    LocalDate(year: year, month: month, day: day)!
}

/// 2026-10-01은 목요일, 2026-10-19는 월요일이다.
private let mondayWednesdayFriday = Recurrence(rule: .weekly(weekdays: [2, 4, 6]), startDay: day(2026, 10, 1))

@Suite("Recurrence")
struct RecurrenceEngineTests {
    @Test func dailyCycleIsOneDay() {
        let daily = Recurrence(rule: .daily, startDay: day(2026, 10, 1))
        let cycle = daily.cycle(containing: day(2026, 10, 19))
        #expect(cycle == RecurrenceCycle(start: day(2026, 10, 19), end: day(2026, 10, 19)))
        #expect(daily.occurrences(in: day(2026, 10, 18)...day(2026, 10, 20)).count == 3)
        #expect(daily.cycle(containing: day(2026, 9, 30)) == nil, "시작일 전에는 주기가 없다")
    }

    @Test func weeklyCycleRunsUntilTheNextChosenWeekday() {
        #expect(mondayWednesdayFriday.cycle(containing: day(2026, 10, 19)) == RecurrenceCycle(start: day(2026, 10, 19), end: day(2026, 10, 20)))
        #expect(mondayWednesdayFriday.cycle(containing: day(2026, 10, 18)) == RecurrenceCycle(start: day(2026, 10, 16), end: day(2026, 10, 18)))
        #expect(mondayWednesdayFriday.cycle(containing: day(2026, 10, 2)) == RecurrenceCycle(start: day(2026, 10, 2), end: day(2026, 10, 4)))
        #expect(mondayWednesdayFriday.cycle(containing: day(2026, 10, 1)) == nil, "첫 발생일(10/2) 전에는 주기가 없다")
    }

    @Test func weeklyWithoutWeekdaysNeverOccurs() {
        let none = Recurrence(rule: .weekly(weekdays: []), startDay: day(2026, 10, 1))
        #expect(none.occurrences(in: day(2026, 10, 1)...day(2026, 10, 31)).isEmpty)
        #expect(none.cycle(containing: day(2026, 10, 19)) == nil)
    }

    @Test func monthlyThirtyFirstFallsOnTheLastDay() {
        let monthly = Recurrence(rule: .monthly(day: 31), startDay: day(2026, 1, 1))
        #expect(monthly.occurrences(in: day(2026, 1, 1)...day(2026, 4, 30)) == [
            day(2026, 1, 31), day(2026, 2, 28), day(2026, 3, 31), day(2026, 4, 30),
        ])
        #expect(monthly.cycle(containing: day(2026, 2, 15)) == RecurrenceCycle(start: day(2026, 1, 31), end: day(2026, 2, 27)))
        #expect(monthly.cycle(containing: day(2026, 2, 28)) == RecurrenceCycle(start: day(2026, 2, 28), end: day(2026, 3, 30)))
        let leapYear = Recurrence(rule: .monthly(day: 30), startDay: day(2028, 1, 1))
        #expect(leapYear.occurrences(in: day(2028, 2, 1)...day(2028, 2, 29)) == [day(2028, 2, 29)])
    }

    @Test func monthlyLastDay() {
        let lastDay = Recurrence(rule: .monthlyLastDay, startDay: day(2026, 1, 1))
        #expect(lastDay.occurrences(in: day(2026, 1, 1)...day(2026, 3, 31)) == [day(2026, 1, 31), day(2026, 2, 28), day(2026, 3, 31)])
        #expect(lastDay.cycle(containing: day(2026, 3, 1)) == RecurrenceCycle(start: day(2026, 2, 28), end: day(2026, 3, 30)))
    }

    @Test func pendingThenMissedWhenTheNextCycleStarts() {
        let cycle = RecurrenceCycle(start: day(2026, 10, 16), end: day(2026, 10, 18))
        #expect(Recurrence.status(of: cycle, today: day(2026, 10, 15), completedOn: nil) == .upcoming)
        #expect(Recurrence.status(of: cycle, today: day(2026, 10, 16), completedOn: nil) == .pending(dayNumber: 1))
        #expect(Recurrence.status(of: cycle, today: day(2026, 10, 18), completedOn: nil) == .pending(dayNumber: 3))
        #expect(Recurrence.status(of: cycle, today: day(2026, 10, 19), completedOn: nil) == .missed)
        #expect(Recurrence.status(of: cycle, today: day(2026, 10, 19), completedOn: day(2026, 10, 17)) == .done(completedOn: day(2026, 10, 17)))
    }

    @Test func endDayStopsNewCyclesButTheLastOneKeepsItsLength() {
        let limited = Recurrence(rule: .weekly(weekdays: [2, 4, 6]), startDay: day(2026, 10, 1), endDay: day(2026, 10, 19))
        #expect(limited.occurrences(in: day(2026, 10, 1)...day(2026, 10, 31)).last == day(2026, 10, 19))
        #expect(limited.cycle(containing: day(2026, 10, 20)) == RecurrenceCycle(start: day(2026, 10, 19), end: day(2026, 10, 20)))
        #expect(limited.cycle(containing: day(2026, 10, 21)) == nil)
    }

    @Test func monthSummaryCountsCyclesStartedSoFar() {
        let completed: Set<LocalDate> = [day(2026, 10, 2), day(2026, 10, 5), day(2026, 10, 9), day(2026, 10, 19)]
        let summary = mondayWednesdayFriday.monthSummary(month: day(2026, 10, 1), today: day(2026, 10, 19), completedCycleStarts: completed)
        #expect(summary.done == 4)
        #expect(summary.total == 8)
        let future = mondayWednesdayFriday.monthSummary(month: day(2026, 11, 1), today: day(2026, 10, 19), completedCycleStarts: completed)
        #expect(future.total == 0)
    }

    @Test func cyclesStartingInARange() {
        let cycles = mondayWednesdayFriday.cycles(startingIn: day(2026, 10, 12)...day(2026, 10, 16))
        #expect(cycles.map { $0.start } == [day(2026, 10, 12), day(2026, 10, 14), day(2026, 10, 16)])
        #expect(cycles.last?.end == day(2026, 10, 18))
    }

    @Test func toggleNeverAddsASecondCompletionToTheSameCycle() {
        let cycle = RecurrenceCycle(start: day(2026, 10, 19), end: day(2026, 10, 20))
        let today = day(2026, 10, 20)
        #expect(RecurrenceToggle.action(for: cycle, completedCycleStarts: [], today: today)
            == .complete(cycleStart: day(2026, 10, 19), completedOn: today))
        #expect(RecurrenceToggle.action(for: cycle, completedCycleStarts: [day(2026, 10, 19)], today: today)
            == .uncomplete(cycleStart: day(2026, 10, 19)))
    }

    @Test func koreanText() {
        #expect(RecurrenceRule.daily.koreanText == "매일")
        #expect(RecurrenceRule.weekly(weekdays: [2, 4, 6]).koreanText == "매주 월·수·금")
        #expect(RecurrenceRule.weekly(weekdays: [1, 7]).koreanText == "매주 토·일")
        #expect(RecurrenceRule.weekly(weekdays: Set(1...7)).koreanText == "매주 모든 요일")
        #expect(RecurrenceRule.monthly(day: 15).koreanText == "매월 15일")
        #expect(RecurrenceRule.monthlyLastDay.koreanText == "매월 말일")
    }
}
