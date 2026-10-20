import DayGridCore
import Foundation
import SwiftData
import Testing
@testable import DayGrid

@MainActor
struct WidgetSnapshotTests {
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

    @Test func sampleDataSnapshotListsTheDueTasks() throws {
        try DefaultCategories.insertIfNeeded(into: context)
        let today = day(2026, 10, 19)
        try SampleData.insert(into: context, today: today, timeZone: seoul)
        let paused = RecurringTask(title: "중지한 일", rule: .daily, startDay: day(2026, 10, 1))
        paused.isActive = false
        context.insert(paused)

        let snapshot = WidgetSnapshotWriter.makeSnapshot(in: context, now: today.date(hour: 8, in: seoul), timeZone: seoul)
        #expect(Set(snapshot.entries.map(\.title)) == ["물 2L 마시기", "헬스장", "관리비 납부"], "사용 중인 반복 할일만 넣는다")
        #expect(Set(snapshot.pending(on: today).map(\.title)) == ["물 2L 마시기", "헬스장"])

        // JSON으로 쓰고 읽어도 같다(위젯이 읽는 형식)
        let decoded = try RecurringSnapshot.decode(snapshot.encoded())
        #expect(decoded.pending(on: today).map(\.title) == snapshot.pending(on: today).map(\.title))
    }

    @Test func checkingATaskRemovesItFromTheSnapshot() throws {
        let today = day(2026, 10, 19)
        let water = RecurringTask(title: "물", rule: .daily, startDay: day(2026, 10, 1))
        context.insert(water)
        try context.save()
        #expect(WidgetSnapshotWriter.makeSnapshot(in: context, now: today.date(hour: 8, in: seoul), timeZone: seoul).pending(on: today).count == 1)

        let cycle = try #require(water.recurrence?.cycle(containing: today))
        water.toggleCompletion(of: cycle, today: today, in: context)
        let snapshot = WidgetSnapshotWriter.makeSnapshot(in: context, now: today.date(hour: 8, in: seoul), timeZone: seoul)
        #expect(snapshot.pending(on: today).isEmpty)
        #expect(snapshot.pending(on: day(2026, 10, 20)).map(\.title) == ["물"], "자정이 지나면 위젯에 다시 나온다")
    }

    @Test func widgetURLOpensTheRecurringTab() {
        #expect(AppRoute(url: RecurringSnapshot.openURL) == .recurring)
        #expect(AppRoute(url: URL(string: "DayGrid://Recurring")!) == .recurring)
        #expect(AppRoute(url: URL(string: "daygrid://calendar")!) == nil)
        #expect(AppRoute(url: URL(string: "https://example.com/recurring")!) == nil)
    }
}
