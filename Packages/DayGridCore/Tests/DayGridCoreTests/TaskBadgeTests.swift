import Foundation
import Testing
@testable import DayGridCore

@Suite("TaskBadge")
struct TaskBadgeTests {
    private func day(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: year, month: month, day: day)!
    }

    /// 2026-11-10(화)
    private var today: LocalDate { day(2026, 11, 10) }

    @Test func countsTasksUpToToday() {
        // 사용자 예시: 할일1은 어제, 할일2는 오늘, 할일3은 내일
        let yesterday = today.adding(days: -1)
        let tomorrow = today.adding(days: 1)
        #expect(TaskBadge.count(on: today, undoneTaskDays: [yesterday, today, tomorrow]) == 2, "내일 할일은 세지 않는다")
        // 어제나 오늘 것 하나를 끝내면 1, 둘 다 끝내면 0(배지 없음)
        #expect(TaskBadge.count(on: today, undoneTaskDays: [today, tomorrow]) == 1)
        #expect(TaskBadge.count(on: today, undoneTaskDays: [yesterday, tomorrow]) == 1)
        #expect(TaskBadge.count(on: today, undoneTaskDays: [tomorrow]) == 0)
        #expect(TaskBadge.count(on: today, undoneTaskDays: []) == 0)
    }

    @Test func longOverdueTasksStayInTheBadge() {
        let days = [day(2026, 9, 1), day(2025, 12, 31), today]
        #expect(TaskBadge.count(on: today, undoneTaskDays: days) == 3)
    }

    @Test func eachTaskCountsOnceEvenOnTheSameDay() {
        // 같은 날 할일 두 개, 기간 할일은 시작일 하나로 들어온다
        #expect(TaskBadge.count(on: today, undoneTaskDays: [today, today, today.adding(days: -3)]) == 3)
    }

    @Test func changesAtTheMidnightsWhenNewTasksStart() {
        let days = [today.adding(days: -1), today, today.adding(days: 1), today.adding(days: 2), today.adding(days: 2)]
        let changes = TaskBadge.changes(after: today, through: today.adding(days: 30), undoneTaskDays: days)
        #expect(changes == [
            TaskBadge.Change(day: today.adding(days: 1), count: 3),
            TaskBadge.Change(day: today.adding(days: 2), count: 5),
        ])
    }

    @Test func noChangesWithoutFutureTasks() {
        let past = [today.adding(days: -2), today]
        #expect(TaskBadge.changes(after: today, through: today.adding(days: 30), undoneTaskDays: past).isEmpty)
        #expect(TaskBadge.changes(after: today, through: today.adding(days: 30), undoneTaskDays: []).isEmpty)
    }

    @Test func changesStayInsideTheRange() {
        let days = [today.adding(days: 3), today.adding(days: 40)]
        let changes = TaskBadge.changes(after: today, through: today.adding(days: 30), undoneTaskDays: days)
        #expect(changes == [TaskBadge.Change(day: today.adding(days: 3), count: 1)])
        #expect(TaskBadge.changes(after: today, through: today, undoneTaskDays: days).isEmpty)
    }
}
