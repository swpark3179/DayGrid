import DayGridCore
import Foundation
import SwiftData
import Testing
@testable import DayGrid

/// "나중에" 목록: 미루기(날짜 비우기와 모양 남기기), 다시 날짜 정하기, 목록 순서.
@MainActor
struct InboxTests {
    let container: ModelContainer
    let seoul = TimeZone(secondsFromGMT: 9 * 3600)!

    var context: ModelContext { container.mainContext }

    init() throws {
        let schema = AppModelContainer.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [configuration])
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: year, month: month, day: day)!
    }

    private func inboxTitles() throws -> [String] {
        let descriptor = FetchDescriptor<Item>(predicate: Item.inboxPredicate, sortBy: [SortDescriptor(\.inboxOrder)])
        return try context.fetch(descriptor).map(\.title)
    }

    @Test func deferringAnAllDayItemKeepsItsLength() throws {
        let trip = Item(title: "출장")
        context.insert(trip)
        trip.scheduleAllDay(from: day(2026, 10, 28), through: day(2026, 11, 3))

        trip.moveToInbox(order: -1, timeZone: seoul)
        #expect(!trip.isScheduled)
        #expect(trip.calendarEntry(in: seoul) == nil)
        #expect(trip.inboxOrder == -1)
        #expect(trip.scheduleHint == ScheduleHint(isAllDay: true, dayCount: 7))

        trip.schedule(on: day(2026, 11, 10), using: trip.scheduleHint, timeZone: seoul)
        #expect(trip.startDayKey == 20_261_110)
        #expect(trip.endDayKey == 20_261_116)
        #expect(trip.isAllDay)
    }

    @Test func deferringATimedItemKeepsItsTime() throws {
        let meeting = Item(title: "회의", isTask: true)
        context.insert(meeting)
        meeting.scheduleTimed(
            start: day(2026, 10, 5).date(hour: 14, in: seoul),
            end: day(2026, 10, 5).date(hour: 15, minute: 30, in: seoul),
            timeZone: seoul
        )
        meeting.toggleCompletion()

        meeting.moveToInbox(order: 0, timeZone: seoul)
        #expect(!meeting.isScheduled)
        #expect(meeting.startDate == nil)
        #expect(meeting.isCompleted, "미뤄도 완료 표시는 그대로 둔다")
        #expect(meeting.scheduleHint == ScheduleHint(isAllDay: false, startMinute: 14 * 60, durationMinutes: 90))

        meeting.schedule(on: day(2026, 10, 21), using: meeting.scheduleHint, timeZone: seoul)
        #expect(meeting.startDate == day(2026, 10, 21).date(hour: 14, in: seoul))
        #expect(meeting.endDate == day(2026, 10, 21).date(hour: 15, minute: 30, in: seoul))
        #expect(meeting.startDayKey == 20_261_021)
    }

    @Test func aQuickTaskIsScheduledAsOneAllDay() {
        let task = Item(title: "책 반납", isTask: true)
        context.insert(task)
        #expect(task.scheduleHint == ScheduleHint())

        task.schedule(on: day(2026, 10, 24), using: task.scheduleHint, timeZone: seoul)
        #expect(task.isAllDay)
        #expect(task.startDayKey == 20_261_024)
        #expect(task.endDayKey == 20_261_024)
    }

    @Test func newItemsGoToTheTopOfTheInbox() throws {
        #expect(Item.topInboxOrder(in: context) == -1)

        for (title, order) in [("둘째", 1.0), ("첫째", 0.0)] {
            let item = Item(title: title, isTask: true)
            item.inboxOrder = order
            context.insert(item)
        }
        let scheduled = Item(title: "날짜 있음")
        scheduled.inboxOrder = -10
        scheduled.scheduleAllDay(from: day(2026, 10, 19), through: day(2026, 10, 19))
        context.insert(scheduled)
        try context.save()
        #expect(Item.topInboxOrder(in: context) == -1, "날짜가 있는 항목의 순서 값은 따지지 않는다")

        let newest = Item(title: "새 할일", isTask: true)
        newest.inboxOrder = Item.topInboxOrder(in: context)
        context.insert(newest)
        try context.save()
        #expect(try inboxTitles() == ["새 할일", "첫째", "둘째"])

        scheduled.moveToInbox(order: Item.topInboxOrder(in: context))
        try context.save()
        #expect(try inboxTitles() == ["날짜 있음", "새 할일", "첫째", "둘째"])
    }

    @Test func duplicateKeepsTheHint() {
        let item = Item(title: "회의")
        context.insert(item)
        item.scheduleTimed(
            start: day(2026, 10, 5).date(hour: 14, in: seoul),
            end: day(2026, 10, 5).date(hour: 15, in: seoul),
            timeZone: seoul
        )
        item.moveToInbox(order: 0, timeZone: seoul)
        #expect(item.duplicate().scheduleHint == item.scheduleHint)
    }
}
