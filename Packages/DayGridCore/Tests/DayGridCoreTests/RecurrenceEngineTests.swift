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

    @Test func dueMeansTheCurrentCycleIsNotDoneYet() {
        let daily = Recurrence(rule: .daily, startDay: day(2026, 10, 1), endDay: day(2026, 10, 31))
        #expect(daily.isDue(on: day(2026, 10, 19), completedCycleStarts: []))
        #expect(!daily.isDue(on: day(2026, 10, 19), completedCycleStarts: [day(2026, 10, 19)]))
        // 어제 한 것은 오늘과 상관없다
        #expect(daily.isDue(on: day(2026, 10, 19), completedCycleStarts: [day(2026, 10, 18)]))
        #expect(!daily.isDue(on: day(2026, 9, 30), completedCycleStarts: []), "시작 전에는 할 일이 없다")
        #expect(!daily.isDue(on: day(2026, 11, 1), completedCycleStarts: []), "끝난 뒤에는 할 일이 없다")

        // 월·수·금: 화요일(10/20)은 월요일 주기 안이다
        #expect(mondayWednesdayFriday.isDue(on: day(2026, 10, 20), completedCycleStarts: []))
        #expect(!mondayWednesdayFriday.isDue(on: day(2026, 10, 20), completedCycleStarts: [day(2026, 10, 19)]))
        #expect(!mondayWednesdayFriday.isDue(on: day(2026, 10, 1), completedCycleStarts: []), "첫 발생일 전")

        // 매월 25일: 10/19는 9/25 주기 안이다
        let monthly = Recurrence(rule: .monthly(day: 25), startDay: day(2026, 9, 1))
        #expect(monthly.isDue(on: day(2026, 10, 19), completedCycleStarts: [day(2026, 8, 25)]))
        #expect(!monthly.isDue(on: day(2026, 10, 19), completedCycleStarts: [day(2026, 9, 25)]))
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

    @Test func summaryPeriodFollowsTheRule() {
        #expect(RecurrenceRule.daily.summaryPeriod == .week)
        #expect(RecurrenceRule.weekly(weekdays: [2, 4, 6]).summaryPeriod == .week)
        #expect(RecurrenceRule.weekly(weekdays: [1]).summaryPeriod == .month, "요일 하나면 이번 주는 늘 1/1이므로 이번 달로 센다")
        #expect(RecurrenceRule.monthly(day: 25).summaryPeriod == .year)
        #expect(RecurrenceRule.monthlyLastDay.summaryPeriod == .year)
    }

    @Test func summaryPeriodRanges() {
        #expect(RecurrenceSummaryPeriod.week.range(containing: day(2026, 10, 19)) == day(2026, 10, 18)...day(2026, 10, 24))
        #expect(RecurrenceSummaryPeriod.week.range(containing: day(2026, 10, 18), firstWeekday: 2) == day(2026, 10, 12)...day(2026, 10, 18))
        #expect(RecurrenceSummaryPeriod.week.range(containing: day(2026, 10, 19), firstWeekday: 9) == day(2026, 10, 18)...day(2026, 10, 24))
        #expect(RecurrenceSummaryPeriod.month.range(containing: day(2026, 2, 10)) == day(2026, 2, 1)...day(2026, 2, 28))
        #expect(RecurrenceSummaryPeriod.year.range(containing: day(2026, 10, 19)) == day(2026, 1, 1)...day(2026, 12, 31))
    }

    @Test func dailySummaryCountsTheWholeWeek() {
        let daily = Recurrence(rule: .daily, startDay: day(2026, 10, 1))
        // 주 첫날(일요일)에도 1/1이 아니다. 남은 날까지 센다.
        let sunday = daily.summary(on: day(2026, 10, 18), completedCycleStarts: [day(2026, 10, 18)])
        #expect(sunday == RecurrenceSummary(period: .week, done: 1, total: 7))
        #expect(sunday?.koreanText == "이번 주 1/7")
        // 이번 주에 만든 할일은 시작일부터 센다. 지난주 완료는 세지 않는다.
        let new = Recurrence(rule: .daily, startDay: day(2026, 10, 20))
        let summary = new.summary(on: day(2026, 10, 20), completedCycleStarts: [day(2026, 10, 17), day(2026, 10, 20)])
        #expect(summary == RecurrenceSummary(period: .week, done: 1, total: 5))
    }

    @Test func weeklySummaryUsesTheWeekOrTheMonth() {
        let completed: Set<LocalDate> = [day(2026, 10, 16), day(2026, 10, 19)]
        #expect(mondayWednesdayFriday.summary(on: day(2026, 10, 20), completedCycleStarts: completed)
            == RecurrenceSummary(period: .week, done: 1, total: 3))
        // 월요일 시작이면 10/18(일)은 10/12 주에 속한다: 10/12, 10/14, 10/16
        #expect(mondayWednesdayFriday.summary(on: day(2026, 10, 18), firstWeekday: 2, completedCycleStarts: completed)
            == RecurrenceSummary(period: .week, done: 1, total: 3))

        let sundays = Recurrence(rule: .weekly(weekdays: [1]), startDay: day(2026, 10, 1))
        let month = sundays.summary(on: day(2026, 10, 19), completedCycleStarts: [day(2026, 10, 4), day(2026, 10, 18)])
        #expect(month == RecurrenceSummary(period: .month, done: 2, total: 4))
        #expect(month?.koreanText == "이번 달 2/4")
    }

    @Test func monthlySummaryUsesTheYear() {
        let bill = Recurrence(rule: .monthly(day: 25), startDay: day(2026, 9, 1))
        let summary = bill.summary(on: day(2026, 10, 19), completedCycleStarts: [day(2026, 9, 25)])
        #expect(summary == RecurrenceSummary(period: .year, done: 1, total: 4), "9/25, 10/25, 11/25, 12/25")
        #expect(summary?.koreanText == "올해 1/4")
        #expect(summary?.fraction == 0.25)
    }

    @Test func noSummaryWithoutCyclesInThePeriod() {
        let later = Recurrence(rule: .daily, startDay: day(2026, 11, 1))
        #expect(later.summary(on: day(2026, 10, 19), completedCycleStarts: []) == nil)
        let ended = Recurrence(rule: .monthly(day: 25), startDay: day(2025, 1, 1), endDay: day(2025, 12, 31))
        #expect(ended.summary(on: day(2026, 3, 1), completedCycleStarts: []) == nil)
        let noWeekdays = Recurrence(rule: .weekly(weekdays: []), startDay: day(2026, 10, 1))
        #expect(noWeekdays.summary(on: day(2026, 10, 19), completedCycleStarts: []) == nil)
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
