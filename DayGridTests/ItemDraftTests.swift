import DayGridCore
import Foundation
import SwiftData
import Testing
@testable import DayGrid

@MainActor
struct ItemDraftTests {
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

    /// 서울 기준 자정부터 지난 분.
    private func minuteOfDay(_ date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoul
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    @Test func newDraftOnAnotherDayStartsAtNine() {
        let categoryID = UUID()
        let now = day(2026, 10, 19).date(hour: 14, minute: 20, in: seoul)
        let draft = ItemDraft.new(on: day(2026, 10, 21), categoryID: categoryID, now: now, timeZone: seoul)
        #expect(minuteOfDay(draft.start) == 9 * 60)
        #expect(draft.end.timeIntervalSince(draft.start) == 3600)
        #expect(LocalDate(draft.start, in: seoul) == day(2026, 10, 21))
        #expect(!draft.isAllDay)
        #expect(!draft.isTask)
        #expect(draft.hasDate)
        #expect(draft.categoryID == categoryID)
        #expect(!draft.canSave)
    }

    @Test func newDraftForTodayStartsAtTheNextHour() {
        let now = day(2026, 10, 19).date(hour: 14, minute: 20, in: seoul)
        let draft = ItemDraft.new(on: day(2026, 10, 19), categoryID: nil, now: now, timeZone: seoul)
        #expect(minuteOfDay(draft.start) == 15 * 60)

        let lateNight = day(2026, 10, 19).date(hour: 23, minute: 30, in: seoul)
        let late = ItemDraft.new(on: day(2026, 10, 19), categoryID: nil, now: lateNight, timeZone: seoul)
        #expect(minuteOfDay(late.start) == 23 * 60)
        #expect(LocalDate(late.start, in: seoul) == day(2026, 10, 19))
    }

    @Test func movingStartKeepsTheDuration() {
        var draft = ItemDraft.new(on: day(2026, 10, 21), categoryID: nil, now: Date(), timeZone: seoul)
        draft.end = draft.start.addingTimeInterval(2 * 3600)
        let later = draft.start.addingTimeInterval(24 * 3600)
        draft.moveStart(to: later)
        #expect(draft.start == later)
        #expect(draft.end.timeIntervalSince(draft.start) == 2 * 3600)
    }

    @Test func earliestEndForAllDayIsMidnightOfTheStartDay() {
        var draft = ItemDraft.new(on: day(2026, 10, 21), categoryID: nil, now: Date(), timeZone: seoul)
        #expect(draft.earliestEnd(timeZone: seoul) == draft.start)
        draft.isAllDay = true
        #expect(draft.earliestEnd(timeZone: seoul) == day(2026, 10, 21).date(in: seoul))
    }

    @Test func applyingAnAllDayDraft() throws {
        try DefaultCategories.insertIfNeeded(into: context)
        let categories = try context.fetch(FetchDescriptor<ItemCategory>(sortBy: [SortDescriptor(\.sortOrder)]))

        var draft = ItemDraft.new(on: day(2026, 10, 28), categoryID: categories[1].id, now: Date(), timeZone: seoul)
        draft.title = "  출장  "
        draft.isAllDay = true
        draft.end = day(2026, 11, 3).date(hour: 10, in: seoul)
        draft.note = "   "

        let item = Item(title: "")
        context.insert(item)
        draft.apply(to: item, categories: categories, timeZone: seoul)

        #expect(item.title == "출장")
        #expect(item.isAllDay)
        #expect(item.startDayKey == 20_261_028)
        #expect(item.endDayKey == 20_261_103)
        #expect(item.startDate == nil)
        #expect(item.body == nil)
        #expect(item.category?.name == "업무")
    }

    @Test func applyingATimedTaskDraft() throws {
        var draft = ItemDraft.new(on: day(2026, 10, 21), categoryID: nil, now: Date(), timeZone: seoul)
        draft.title = "보고서 쓰기"
        draft.isTask = true
        draft.note = "초안부터"

        let item = Item(title: "")
        context.insert(item)
        draft.apply(to: item, categories: [], timeZone: seoul)

        #expect(!item.isAllDay)
        #expect(item.isTask)
        #expect(item.startDate == draft.start)
        #expect(item.endDate == draft.end)
        #expect(item.startDayKey == 20_261_021)
        #expect(item.body == "초안부터")
        #expect(item.category == nil)
    }

    @Test func turningATaskBackIntoAnEventClearsCompletion() {
        let item = Item(title: "할일", isTask: true)
        context.insert(item)
        item.scheduleAllDay(from: day(2026, 10, 21), through: day(2026, 10, 21))
        item.toggleCompletion()
        #expect(item.isCompleted)

        var draft = ItemDraft(item: item, timeZone: seoul)
        draft.isTask = false
        draft.apply(to: item, categories: [], timeZone: seoul)
        #expect(!item.isCompleted)
    }

    @Test func draftRoundTripsAnExistingItem() throws {
        let original = Item(title: "치과")
        context.insert(original)
        original.scheduleTimed(
            start: day(2026, 10, 5).date(hour: 14, in: seoul),
            end: day(2026, 10, 5).date(hour: 15, minute: 30, in: seoul),
            timeZone: seoul
        )
        original.body = "스케일링"

        let draft = ItemDraft(item: original, timeZone: seoul)
        #expect(draft.title == "치과")
        #expect(draft.start == original.startDate)
        #expect(draft.end == original.endDate)
        #expect(draft.note == "스케일링")
        #expect(draft.canSave)

        let copy = Item(title: "")
        context.insert(copy)
        draft.apply(to: copy, categories: [], timeZone: seoul)
        #expect(copy.startDayKey == original.startDayKey)
        #expect(copy.startDate == original.startDate)
        #expect(copy.endDate == original.endDate)
        #expect(copy.body == original.body)
    }

    @Test func undatedItemKeepsItsPlaceInTheInbox() {
        let item = Item(title: "책", isTask: true)
        item.inboxOrder = 2
        context.insert(item)

        var draft = ItemDraft(item: item, today: day(2026, 10, 19), timeZone: seoul)
        #expect(!draft.hasDate)
        #expect(draft.isAllDay)
        #expect(LocalDate(draft.start, in: seoul) == day(2026, 10, 19))

        draft.title = "책 반납"
        draft.apply(to: item, categories: [], inboxOrder: -5, timeZone: seoul)
        #expect(item.title == "책 반납")
        #expect(!item.isScheduled)
        #expect(item.inboxOrder == 2)
        #expect(item.scheduleHint == ScheduleHint())
    }

    @Test func turningOffTheDateMovesTheItemToTheInbox() {
        let item = Item(title: "치과")
        context.insert(item)
        item.scheduleTimed(
            start: day(2026, 10, 5).date(hour: 14, in: seoul),
            end: day(2026, 10, 5).date(hour: 15, minute: 30, in: seoul),
            timeZone: seoul
        )

        var draft = ItemDraft(item: item, timeZone: seoul)
        #expect(draft.hasDate)
        draft.hasDate = false
        draft.apply(to: item, categories: [], inboxOrder: -3, timeZone: seoul)
        #expect(!item.isScheduled)
        #expect(item.startDate == nil)
        #expect(item.inboxOrder == -3)
        #expect(item.scheduleHint == ScheduleHint(isAllDay: false, startMinute: 14 * 60, durationMinutes: 90))
    }

    @Test func undatedDraftStartsFromTheHint() {
        let item = Item(title: "치과")
        context.insert(item)
        item.scheduleTimed(
            start: day(2026, 10, 5).date(hour: 14, in: seoul),
            end: day(2026, 10, 5).date(hour: 15, minute: 30, in: seoul),
            timeZone: seoul
        )
        item.moveToInbox(order: 0, timeZone: seoul)

        var draft = ItemDraft(item: item, today: day(2026, 10, 21), timeZone: seoul)
        #expect(!draft.hasDate)
        #expect(!draft.isAllDay)
        #expect(draft.start == day(2026, 10, 21).date(hour: 14, in: seoul))
        #expect(draft.end == day(2026, 10, 21).date(hour: 15, minute: 30, in: seoul))

        draft.hasDate = true
        draft.apply(to: item, categories: [], timeZone: seoul)
        #expect(item.startDayKey == 20_261_021)
        #expect(item.startDate == draft.start)
    }

    @Test func duplicateCopiesTheScheduleButNotCompletion() throws {
        try DefaultCategories.insertIfNeeded(into: context)
        let category = try context.fetch(FetchDescriptor<ItemCategory>()).first
        let original = Item(title: "운동", isTask: true, category: category)
        context.insert(original)
        original.scheduleAllDay(from: day(2026, 10, 15), through: day(2026, 10, 16))
        original.body = "30분"
        original.toggleCompletion()

        let copy = original.duplicate()
        context.insert(copy)
        try context.save()

        #expect(copy.id != original.id)
        #expect(copy.title == "운동")
        #expect(copy.isTask)
        #expect(copy.startDayKey == original.startDayKey)
        #expect(copy.endDayKey == original.endDayKey)
        #expect(copy.body == "30분")
        #expect(copy.category?.id == category?.id)
        #expect(!copy.isCompleted)
        #expect(try context.fetch(FetchDescriptor<Item>()).count == 2)
    }
}
