import Foundation
import Testing
@testable import DayGridCore

private let seoul = TimeZone(secondsFromGMT: 9 * 3600)!

private func day(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
    LocalDate(year: year, month: month, day: day)!
}

private func at(_ date: LocalDate, _ hour: Int, _ minute: Int = 0) -> Date {
    date.date(hour: hour, minute: minute, in: seoul)
}

private func uuid(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
}

/// 2026-10-19(월) 08:00, 서울
private let now = at(day(2026, 10, 19), 8)

private func plan(
    items: [ReminderPlanner.ItemInput] = [],
    birthdays: [ReminderPlanner.BirthdayInput] = [],
    birthdaySettings: ReminderPlanner.BirthdaySettings = .off,
    recurring: [ReminderPlanner.RecurringInput] = [],
    limit: Int = ReminderPlanner.defaultLimit
) -> [PlannedReminder] {
    ReminderPlanner.plan(
        items: items, birthdays: birthdays, birthdaySettings: birthdaySettings, recurring: recurring,
        now: now, timeZone: seoul, limit: limit
    )
}

private func dailyTask(_ number: Int, completed: Set<LocalDate> = []) -> ReminderPlanner.RecurringInput {
    ReminderPlanner.RecurringInput(
        id: uuid(number),
        title: "반복 \(number)",
        recurrence: Recurrence(rule: .daily, startDay: day(2026, 10, 1)),
        notifyMinute: 9 * 60,
        completedCycleStarts: completed
    )
}

@Suite("ReminderPlanner")
struct ReminderPlannerTests {
    @Test func timedItemOffsetsAndPastRemindersAreSkipped() {
        let meeting = ReminderPlanner.ItemInput(
            id: uuid(1), title: "회의", isTask: true, isCompleted: false, isAllDay: false,
            startDay: day(2026, 10, 19), startDate: at(day(2026, 10, 19), 10),
            options: [.atStart, .tenMinutesBefore, .oneDayBefore]
        )
        let result = plan(items: [meeting])
        #expect(result.map { $0.fireDate } == [at(day(2026, 10, 19), 9, 50), at(day(2026, 10, 19), 10)])
        #expect(result.first?.body == "10분 전 · 오전 10시 시작")
        #expect(result.last?.body == "지금 시작")
        #expect(result.first?.kind == .item(id: uuid(1), isTask: true))
        #expect(result.first?.day == day(2026, 10, 19))
    }

    @Test func allDayItemsRemindAtNineInTheMorning() {
        let trip = ReminderPlanner.ItemInput(
            id: uuid(2), title: "출장", isTask: false, isCompleted: false, isAllDay: true,
            startDay: day(2026, 10, 20), startDate: nil, options: [.sameDayMorning, .previousDayMorning, .atStart]
        )
        let result = plan(items: [trip])
        #expect(result.map { $0.fireDate } == [at(day(2026, 10, 19), 9), at(day(2026, 10, 20), 9)])
        #expect(result.map { $0.body } == ["내일 10월 20일 (화)", "오늘 10월 20일 (화)"])
    }

    @Test func completedTasksAndUndatedItemsHaveNoReminders() {
        let done = ReminderPlanner.ItemInput(
            id: uuid(3), title: "끝", isTask: true, isCompleted: true, isAllDay: false,
            startDay: day(2026, 10, 19), startDate: at(day(2026, 10, 19), 12), options: [.atStart]
        )
        let someday = ReminderPlanner.ItemInput(
            id: uuid(4), title: "언젠가", isTask: true, isCompleted: false, isAllDay: true,
            startDay: nil, startDate: nil, options: [.sameDayMorning]
        )
        #expect(plan(items: [done, someday]).isEmpty)
    }

    @Test func birthdayDaysBefore() {
        let friend = ReminderPlanner.BirthdayInput(id: uuid(5), name: "김민수", birthday: Birthday(month: 10, day: 22))
        let result = plan(birthdays: [friend], birthdaySettings: .init(daysBefore: [0, 3]))
        #expect(result.map { $0.fireDate } == [at(day(2026, 10, 19), 9), at(day(2026, 10, 22), 9)])
        #expect(result.map { $0.title } == ["🎂 김민수 생일", "🎂 김민수 생일"])
        #expect(result.map { $0.body } == ["3일 남았습니다 · 10월 22일 (목)", "오늘입니다"])
        #expect(result.allSatisfy { $0.day == day(2026, 10, 22) })
        #expect(plan(birthdays: [friend], birthdaySettings: .off).isEmpty)
    }

    @Test func recurringRemindsOnceWhenEachCycleStarts() {
        let result = plan(recurring: [dailyTask(6, completed: [day(2026, 10, 19)])])
        // 오늘(10/19) 주기는 이미 완료했고, 30일 범위의 끝(11/18 0시) 전까지 하루에 하나씩.
        #expect(result.count == 29)
        #expect(result.first?.fireDate == at(day(2026, 10, 20), 9))
        #expect(result.last?.fireDate == at(day(2026, 11, 17), 9))
        #expect(Set(result.map { $0.identifier }).count == result.count, "주기마다 알림은 하나")
        #expect(result.first?.kind == .recurring(taskID: uuid(6), cycleStart: day(2026, 10, 20)))
        #expect(result.first?.body == "매일 반복 할일")

        let weekly = ReminderPlanner.RecurringInput(
            id: uuid(7), title: "헬스장",
            recurrence: Recurrence(rule: .weekly(weekdays: [2, 4, 6]), startDay: day(2026, 10, 1)),
            notifyMinute: 7 * 60, completedCycleStarts: []
        )
        let weeklyResult = plan(recurring: [weekly])
        // 10/19 07:00은 이미 지났다. 10/21(수)부터.
        #expect(weeklyResult.first?.fireDate == at(day(2026, 10, 21), 7))
        let silent = ReminderPlanner.RecurringInput(
            id: uuid(8), title: "조용히", recurrence: weekly.recurrence, notifyMinute: -1, completedCycleStarts: []
        )
        #expect(plan(recurring: [silent]).isEmpty)
    }

    @Test func keepsOnlyTheNearestSixty() {
        let tasks = (10..<14).map { dailyTask($0) }
        let result = plan(recurring: tasks)
        #expect(result.count == 60, "iOS 대기 알림 64개 제한 아래로 고른다")
        let all = plan(recurring: tasks, limit: 1000)
        #expect(all.count == 4 * 30)
        #expect(result == Array(all.prefix(60)))
        #expect(zip(result, result.dropFirst()).allSatisfy { $0.fireDate <= $1.fireDate })
        #expect(plan(recurring: tasks, limit: 10).count == 10)
    }

    @Test func identifiersAreStable() {
        let first = plan(recurring: [dailyTask(20)]).map { $0.identifier }
        let second = plan(recurring: [dailyTask(20)]).map { $0.identifier }
        #expect(first == second)
        #expect(first.first == "daygrid.recurring.00000000-0000-0000-0000-000000000020.20261019")
    }

    @Test func optionMasks() {
        let mask = ReminderOption.mask(of: [.atStart, .oneHourBefore])
        #expect(mask == 0b101)
        #expect(ReminderOption.options(in: mask) == [.atStart, .oneHourBefore])
        #expect(ReminderOption.options(in: 0).isEmpty)
    }
}
