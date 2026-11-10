import DayGridCore
import Foundation
import SwiftData
import Testing
@testable import DayGrid

/// 앱 아이콘 배지에 넣을 할일(`NotificationScheduler.badgeTaskDays`)과 그 수(Core `TaskBadge`).
@MainActor
struct AppBadgeTests {
    let container: ModelContainer
    let seoul = TimeZone(secondsFromGMT: 9 * 3600)!
    /// 2026-11-10(화)
    let today = LocalDate(year: 2026, month: 11, day: 10)!

    var context: ModelContext { container.mainContext }

    init() throws {
        let schema = AppModelContainer.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [configuration])
    }

    @discardableResult
    private func allDayTask(_ title: String, _ offset: Int, through endOffset: Int? = nil) -> Item {
        let item = Item(title: title, isTask: true)
        item.scheduleAllDay(from: today.adding(days: offset), through: today.adding(days: endOffset ?? offset))
        context.insert(item)
        return item
    }

    private var badge: Int {
        TaskBadge.count(on: today, undoneTaskDays: NotificationScheduler.badgeTaskDays(in: context, timeZone: seoul))
    }

    @Test func countsUndoneDatedTasksUpToToday() throws {
        // 사용자 예시: 어제, 오늘(시간 할일), 내일
        let yesterday = allDayTask("어제 할일", -1)
        let todayTask = Item(title: "오늘 할일", isTask: true)
        todayTask.scheduleTimed(start: today.date(hour: 15, in: seoul), end: today.date(hour: 16, in: seoul), timeZone: seoul)
        context.insert(todayTask)
        allDayTask("내일 할일", 1)
        // 세지 않는 것: 끝낸 할일, 날짜 없는 "나중에" 할일, 할일이 아닌 일정
        allDayTask("끝낸 할일", -2).toggleCompletion()
        context.insert(Item(title: "나중에 할일", isTask: true))
        let event = Item(title: "오늘 일정")
        event.scheduleAllDay(from: today, through: today)
        context.insert(event)
        try context.save()

        #expect(badge == 2, "내일 할일은 배지에 들어가지 않는다")
        yesterday.toggleCompletion()
        #expect(badge == 1)
        todayTask.toggleCompletion()
        #expect(badge == 0, "둘 다 끝내면 배지가 없다")
    }

    @Test func aRangeTaskCountsOnceFromItsFirstDay() throws {
        allDayTask("이사 준비", -2, through: 3)
        allDayTask("다음 주 할일", 5, through: 7)
        try context.save()
        #expect(badge == 1)
        let days = NotificationScheduler.badgeTaskDays(in: context, timeZone: seoul)
        #expect(TaskBadge.changes(after: today, through: today.adding(days: 30), undoneTaskDays: days)
            == [TaskBadge.Change(day: today.adding(days: 5), count: 2)])
    }

    @Test func timedTasksUseTheirRealDate() throws {
        // 서울 11/11 00:30에 시작하는 할일을 UTC 기준으로 저장하면 색인(startDayKey)은 11/10이다.
        let utc = TimeZone(secondsFromGMT: 0)!
        let task = Item(title: "자정 넘어 할일", isTask: true)
        let start = today.adding(days: 1).date(hour: 0, minute: 30, in: seoul)
        task.scheduleTimed(start: start, end: start.addingTimeInterval(1800), timeZone: utc)
        context.insert(task)
        try context.save()
        #expect(task.startDayKey == today.yyyymmdd)

        #expect(NotificationScheduler.badgeTaskDays(in: context, timeZone: seoul) == [today.adding(days: 1)])
        #expect(badge == 0, "서울에서는 내일 할일이다")
    }

    @Test func sampleDataHasNoDatedTasks() throws {
        // 샘플의 할일은 모두 "나중에" 목록에 있다. 날짜가 있는 샘플은 일정뿐이다.
        try DefaultCategories.insertIfNeeded(into: context)
        try SampleData.insert(into: context, today: today, timeZone: seoul)
        #expect(NotificationScheduler.badgeTaskDays(in: context, timeZone: seoul).isEmpty)
    }
}
