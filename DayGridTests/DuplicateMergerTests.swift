import DayGridCore
import Foundation
import SwiftData
import Testing
@testable import DayGrid

@MainActor
struct DuplicateMergerTests {
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

    @Test func seedCategoriesFromTwoDevicesBecomeOne() throws {
        // 이 기기에서 먼저 만들고 이름을 고친 기본 카테고리
        let seed = DefaultCategories.seeds[1]
        let original = ItemCategory(id: seed.id, name: "회사", colorHex: "#000000", sortOrder: 1)
        original.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        // 다른 기기가 iCloud에서 받기 전에 넣은 같은 기본 카테고리
        let copy = ItemCategory(id: seed.id, name: seed.name, colorHex: seed.colorHex, sortOrder: 1)
        copy.createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let other = ItemCategory(name: "취미", colorHex: "#FFFFFF", sortOrder: 5)
        for category in [original, copy, other] {
            context.insert(category)
        }

        let meeting = Item(title: "회의", category: original)
        let report = Item(title: "보고서", isTask: true, category: copy)
        let gym = RecurringTask(title: "헬스장", rule: .daily, startDay: day(2026, 10, 1))
        context.insert(meeting)
        context.insert(report)
        context.insert(gym)
        gym.category = copy
        try context.save()

        DuplicateMerger.mergeAll(in: context)

        let categories = try context.fetch(FetchDescriptor<ItemCategory>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(categories.map(\.name) == ["회사", "취미"])
        let kept = try #require(categories.first)
        #expect(kept.colorHex == "#000000")
        #expect(meeting.category?.name == "회사")
        #expect(report.category?.name == "회사")
        #expect(gym.category?.name == "회사")
        #expect(Set((kept.items ?? []).map(\.title)) == ["회의", "보고서"])
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 2)
    }

    @Test func distinctCategoriesAreLeftAlone() throws {
        try DefaultCategories.insertIfNeeded(into: context)
        DuplicateMerger.mergeAll(in: context)
        #expect(try context.fetchCount(FetchDescriptor<ItemCategory>()) == DefaultCategories.seeds.count)
        #expect(DuplicateMerger.mergeCategories(in: context) == 0)
    }

    @Test func duplicateCompletionsKeepTheEarliestCheck() throws {
        let water = RecurringTask(title: "물", rule: .daily, startDay: day(2026, 10, 1))
        let gym = RecurringTask(title: "헬스장", rule: .weekly(weekdays: [2, 4, 6]), startDay: day(2026, 10, 1))
        context.insert(water)
        context.insert(gym)
        func complete(_ task: RecurringTask, cycle: LocalDate, on done: LocalDate) {
            let completion = RecurrenceCompletion(cycleStart: cycle, completedOn: done)
            context.insert(completion)
            completion.task = task
        }
        // 두 기기에서 같은 주기(10/19 시작)를 각각 체크했다
        complete(gym, cycle: day(2026, 10, 19), on: day(2026, 10, 20))
        complete(gym, cycle: day(2026, 10, 19), on: day(2026, 10, 19))
        // 다른 할일의 같은 시작일, 같은 할일의 다른 주기는 그대로 둔다
        complete(water, cycle: day(2026, 10, 19), on: day(2026, 10, 19))
        complete(gym, cycle: day(2026, 10, 16), on: day(2026, 10, 16))
        try context.save()

        #expect(DuplicateMerger.mergeCompletions(in: context) == 1)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<RecurrenceCompletion>()) == 3)
        #expect(gym.completionDays == [day(2026, 10, 19): day(2026, 10, 19), day(2026, 10, 16): day(2026, 10, 16)])
        #expect(water.completionDays == [day(2026, 10, 19): day(2026, 10, 19)])
    }
}
