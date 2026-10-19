import DayGridCore
import Foundation
import SwiftData
import Testing
@testable import DayGrid

@MainActor
struct ItemStoreTests {
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

    private func insertAllDay(_ title: String, _ start: LocalDate, _ end: LocalDate) {
        let item = Item(title: title)
        item.scheduleAllDay(from: start, through: end)
        context.insert(item)
    }

    private func titles(overlapping range: ClosedRange<LocalDate>) throws -> Set<String> {
        let descriptor = FetchDescriptor<Item>(predicate: Item.predicate(overlapping: range))
        return Set(try context.fetch(descriptor).map(\.title))
    }

    @Test func predicateFindsOnlyItemsOverlappingTheRange() throws {
        insertAllDay("10월 초", day(2026, 10, 1), day(2026, 10, 3))
        insertAllDay("9월 말부터", day(2026, 9, 20), day(2026, 9, 30))
        insertAllDay("9월 초", day(2026, 9, 1), day(2026, 9, 2))
        insertAllDay("크리스마스", day(2026, 12, 24), day(2026, 12, 25))
        let meeting = Item(title: "회의")
        meeting.scheduleTimed(
            start: day(2026, 10, 19).date(hour: 10, in: seoul),
            end: day(2026, 10, 19).date(hour: 11, in: seoul),
            timeZone: seoul
        )
        context.insert(meeting)
        context.insert(Item(title: "나중에 할일", isTask: true))
        try context.save()

        let october = MonthLayout.visibleDays(of: day(2026, 10, 1))
        #expect(try titles(overlapping: october) == Set(["10월 초", "9월 말부터", "회의"]))
    }

    @Test func calendarEntryFollowsTheSchedule() {
        let trip = Item(title: "여행")
        trip.scheduleAllDay(from: day(2026, 10, 1), through: day(2026, 10, 3))
        #expect(trip.calendarEntry(in: seoul) == CalendarEntry.allDay(id: trip.id, from: day(2026, 10, 1), through: day(2026, 10, 3)))

        let lateMeeting = Item(title: "늦은 회의")
        lateMeeting.scheduleTimed(
            start: day(2026, 10, 19).date(hour: 22, in: seoul),
            end: day(2026, 10, 20).date(hour: 0, in: seoul),
            timeZone: seoul
        )
        let entry = lateMeeting.calendarEntry(in: seoul)
        #expect(entry?.startDay == day(2026, 10, 19))
        #expect(entry?.endDay == day(2026, 10, 19))
        #expect(entry?.startMinute == 22 * 60)
        #expect(entry?.style == .chip)
        #expect(lateMeeting.startDayKey == 20_261_019)
        #expect(lateMeeting.endDayKey == 20_261_019)

        let someday = Item(title: "언젠가", isTask: true)
        #expect(!someday.isScheduled)
        #expect(someday.calendarEntry(in: seoul) == nil)

        lateMeeting.unschedule()
        #expect(!lateMeeting.isScheduled)
        #expect(lateMeeting.calendarEntry(in: seoul) == nil)
    }

    @Test func defaultCategoriesAreInsertedOnlyOnce() throws {
        try DefaultCategories.insertIfNeeded(into: context)
        try DefaultCategories.insertIfNeeded(into: context)
        let categories = try context.fetch(FetchDescriptor<ItemCategory>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(categories.map(\.name) == ["개인", "업무", "가족", "건강", "기타"])
        #expect(categories.map(\.id) == DefaultCategories.seeds.map(\.id))
    }

    @Test func deletingACategoryKeepsItsItems() throws {
        let category = ItemCategory(name: "임시", colorHex: "#E03131", sortOrder: 0)
        context.insert(category)
        let item = Item(title: "일정")
        item.scheduleAllDay(from: day(2026, 10, 19), through: day(2026, 10, 19))
        context.insert(item)
        item.category = category
        try context.save()

        context.delete(category)
        try context.save()

        let items = try context.fetch(FetchDescriptor<Item>())
        #expect(items.map(\.title) == ["일정"])
        #expect(items.first?.category == nil)
    }

    @Test func sampleDataFillsTheScreenshotMonth() throws {
        try DefaultCategories.insertIfNeeded(into: context)
        let today = day(2026, 10, 19)
        try SampleData.insert(into: context, today: today, timeZone: seoul)

        let items = try context.fetch(FetchDescriptor<Item>())
        let scheduled = items.filter { $0.isScheduled }
        #expect(items.count == 20)
        #expect(scheduled.count == 15)
        #expect(items.allSatisfy { $0.category != nil })
        #expect(try titles(overlapping: MonthLayout.visibleDays(of: today)).count == 15)
        #expect(try titles(overlapping: MonthLayout.visibleDays(of: day(2026, 11, 1))) == Set(["출장"]))

        let inbox = try context.fetch(FetchDescriptor<Item>(predicate: Item.inboxPredicate, sortBy: [SortDescriptor(\.inboxOrder)]))
        #expect(inbox.map { $0.title } == ["책 반납하기", "선물 고르기", "건강검진 예약", "대청소", "우산 사기"])
        #expect(inbox.map { $0.isCompleted } == [false, false, false, false, true])
        let cleaning = try #require(inbox.first { $0.title == "대청소" })
        #expect(!cleaning.isTask)
        #expect(cleaning.scheduleHint == ScheduleHint(isAllDay: true, dayCount: 2))

        // 생일 4명(30일 안 3명), 개인 휴일 1개, 반복 할일 3개와 완료 기록 9개
        let people = try context.fetch(FetchDescriptor<Person>())
        #expect(Set(people.map(\.name)) == ["김민수", "엄마", "아빠", "이지은"])
        #expect(people.first { $0.name == "엄마" }?.isLunar == true)
        let holidays = try context.fetch(FetchDescriptor<PersonalHoliday>())
        #expect(holidays.map(\.name) == ["회사 창립기념일"])
        #expect(holidays.first?.startDay == day(2026, 10, 16))
        let tasks = try context.fetch(FetchDescriptor<RecurringTask>(sortBy: [SortDescriptor(\.startDayKey)]))
        #expect(tasks.map(\.title) == ["관리비 납부", "헬스장", "물 2L 마시기"])
        #expect(try context.fetchCount(FetchDescriptor<RecurrenceCompletion>()) == 9)
        #expect(tasks.map { $0.completions?.count ?? 0 } == [1, 3, 5])
    }
}
