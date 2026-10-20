import DayGridCore
import Foundation
import SwiftData
import Testing
@testable import DayGrid

@MainActor
struct RecurringTaskTests {
    let container: ModelContainer

    var context: ModelContext { container.mainContext }

    init() throws {
        let schema = AppModelContainer.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [configuration])
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: year, month: month, day: day)!
    }

    private func completionCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<RecurrenceCompletion>())
    }

    // MARK: - 미완료(배지)

    @Test func sampleDataHasTwoDueTasksToday() throws {
        try DefaultCategories.insertIfNeeded(into: context)
        let today = day(2026, 10, 19)
        try SampleData.insert(into: context, today: today)

        let tasks = try context.fetch(FetchDescriptor<RecurringTask>(predicate: RecurringTask.activePredicate))
        // 물 2L(매일)과 헬스장(월요일 주기)은 아직 안 했고, 관리비는 9/25 주기를 이미 냈다
        #expect(Set(tasks.filter { $0.isDue(on: today) }.map(\.title)) == ["물 2L 마시기", "헬스장"])

        // 체크하면 배지에서 빠진다
        let water = try #require(tasks.first { $0.title == "물 2L 마시기" })
        let cycle = try #require(water.recurrence?.cycle(containing: today))
        water.toggleCompletion(of: cycle, today: today, in: context)
        #expect(!water.isDue(on: today))
        #expect(water.isDue(on: day(2026, 10, 20)), "다음 날은 새 주기다")
    }

    @Test func tasksBeforeTheirStartAreNotDue() {
        let later = RecurringTask(title: "나중", rule: .daily, startDay: day(2026, 11, 1))
        #expect(!later.isDue(on: day(2026, 10, 19)))
        later.startDayKey = 0
        #expect(!later.isDue(on: day(2026, 10, 19)), "시작일이 없으면 주기가 없다")
    }

    // MARK: - 규칙 저장

    @Test func ruleRoundTripsThroughTheStoredFields() {
        let task = RecurringTask(title: "물", rule: .daily, startDay: day(2026, 10, 1))
        context.insert(task)
        #expect(task.ruleKind == 0)
        #expect(task.rule == .daily)

        task.rule = .weekly(weekdays: [2, 4, 6])
        #expect(task.ruleKind == 1)
        #expect(task.weekdayMask == 84)
        #expect(task.rule == .weekly(weekdays: [2, 4, 6]))

        task.rule = .monthly(day: 31)
        #expect(task.ruleKind == 2)
        #expect(task.monthDay == 31)
        #expect(task.rule == .monthly(day: 31))

        task.rule = .monthlyLastDay
        #expect(task.ruleKind == 2)
        #expect(task.monthDay == 0)
        #expect(task.rule == .monthlyLastDay)
    }

    @Test func monthDayIsClampedToAValidDay() {
        let task = RecurringTask(title: "관리비", rule: .monthly(day: 40), startDay: day(2026, 10, 1))
        #expect(task.monthDay == 31)
        task.rule = .monthly(day: -3)
        #expect(task.monthDay == 1)
        #expect(task.rule == .monthly(day: 1))
    }

    @Test func recurrenceUsesTheStartAndEndDays() {
        let task = RecurringTask(title: "물", rule: .daily, startDay: day(2026, 10, 1))
        #expect(task.recurrence == Recurrence(rule: .daily, startDay: day(2026, 10, 1)))
        task.endDayKey = 20_261_031
        #expect(task.recurrence?.endDay == day(2026, 10, 31))
        task.startDayKey = 0
        #expect(task.recurrence == nil)
    }

    // MARK: - 체크

    @Test func togglingTheSameCycleNeverAddsASecondRecord() throws {
        // 월·수·금: 10/19(월) 주기는 10/19–10/20
        let task = RecurringTask(title: "헬스장", rule: .weekly(weekdays: [2, 4, 6]), startDay: day(2026, 10, 5))
        context.insert(task)
        let monday = day(2026, 10, 19)
        let cycle = try #require(task.recurrence?.cycle(containing: monday))
        #expect(cycle == RecurrenceCycle(start: monday, end: day(2026, 10, 20)))

        task.toggleCompletion(of: cycle, today: monday, in: context)
        #expect(try completionCount() == 1)
        #expect(task.completionDays == [monday: monday])

        // 다음 날 같은 주기를 다시 누르면 기록을 지운다(둘째 기록을 만들지 않는다)
        task.toggleCompletion(of: cycle, today: day(2026, 10, 20), in: context)
        #expect(try completionCount() == 0)
        #expect(task.completionDays.isEmpty)

        task.toggleCompletion(of: cycle, today: day(2026, 10, 20), in: context)
        #expect(try completionCount() == 1)
        #expect(task.completionDays == [monday: day(2026, 10, 20)])
    }

    @Test func cycleStatusIsComputedFromTheCompletions() throws {
        let task = RecurringTask(title: "헬스장", rule: .weekly(weekdays: [2, 4, 6]), startDay: day(2026, 10, 5))
        context.insert(task)
        let completion = RecurrenceCompletion(cycleStart: day(2026, 10, 14), completedOn: day(2026, 10, 15))
        context.insert(completion)
        completion.task = task
        try context.save()

        let today = day(2026, 10, 20)
        let done = try #require(task.cycleStatus(on: day(2026, 10, 15), today: today))
        #expect(done.cycle == RecurrenceCycle(start: day(2026, 10, 14), end: day(2026, 10, 15)))
        #expect(done.status == .done(completedOn: day(2026, 10, 15)))

        let missed = try #require(task.cycleStatus(on: day(2026, 10, 17), today: today))
        #expect(missed.cycle == RecurrenceCycle(start: day(2026, 10, 16), end: day(2026, 10, 18)))
        #expect(missed.status == .missed)

        let pending = try #require(task.cycleStatus(on: today, today: today))
        #expect(pending.status == .pending(dayNumber: 2))

        // 시작일 전에는 주기가 없다
        #expect(task.cycleStatus(on: day(2026, 10, 1), today: today)?.cycle == nil)
    }

    // MARK: - 조회와 삭제

    @Test func activePredicateSkipsPausedTasks() throws {
        let running = RecurringTask(title: "진행", rule: .daily, startDay: day(2026, 10, 1))
        let paused = RecurringTask(title: "중지", rule: .daily, startDay: day(2026, 10, 1))
        paused.isActive = false
        context.insert(running)
        context.insert(paused)
        try context.save()

        let active = try context.fetch(FetchDescriptor<RecurringTask>(predicate: RecurringTask.activePredicate))
        #expect(active.map(\.title) == ["진행"])
    }

    @Test func deletingATaskDeletesItsCompletions() throws {
        let task = RecurringTask(title: "물", rule: .daily, startDay: day(2026, 10, 1))
        context.insert(task)
        for offset in 0..<3 {
            let date = day(2026, 10, 1).adding(days: offset)
            let completion = RecurrenceCompletion(cycleStart: date, completedOn: date)
            context.insert(completion)
            completion.task = task
        }
        try context.save()
        #expect(try completionCount() == 3)

        context.delete(task)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<RecurringTask>()) == 0)
        #expect(try completionCount() == 0)
    }
}
