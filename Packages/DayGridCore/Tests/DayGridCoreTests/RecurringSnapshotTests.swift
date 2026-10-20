import Foundation
import Testing
@testable import DayGridCore

@Suite("RecurringSnapshot")
struct RecurringSnapshotTests {
    private func day(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: year, month: month, day: day)!
    }

    private func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    private var snapshot: RecurringSnapshot {
        RecurringSnapshot.make(
            generatedAt: Date(timeIntervalSince1970: 1_792_400_000),
            today: day(2026, 10, 19),
            tasks: [
                (uuid(1), "물 2L 마시기", Recurrence(rule: .daily, startDay: day(2026, 10, 5)), [day(2026, 10, 18), day(2026, 7, 1)]),
                (uuid(2), "헬스장", Recurrence(rule: .weekly(weekdays: [2, 4, 6]), startDay: day(2026, 10, 1)), [day(2026, 10, 16)]),
                (uuid(3), "관리비 납부", Recurrence(rule: .monthly(day: 25), startDay: day(2026, 9, 1)), [day(2026, 9, 25)]),
            ]
        )
    }

    @Test func pendingFollowsTheDay() {
        // 10/19(월): 물(오늘 주기 미완료), 헬스장(월요일 주기 미완료). 관리비는 9/25 주기를 했다.
        #expect(snapshot.pending(on: day(2026, 10, 19)).map(\.title) == ["물 2L 마시기", "헬스장"])
        // 10/25(일): 관리비 새 주기가 시작되고, 헬스장은 금요일(10/23) 주기 안이다
        #expect(snapshot.pending(on: day(2026, 10, 25)).map(\.title) == ["물 2L 마시기", "헬스장", "관리비 납부"])
    }

    @Test func oldCompletionsAreLeftOut() {
        let water = snapshot.entries[0]
        #expect(water.completedCycleStarts == [day(2026, 10, 18)], "62일보다 오래된 완료는 넣지 않는다")
    }

    @Test func roundTripsThroughJSON() throws {
        let data = try snapshot.encoded()
        let decoded = try RecurringSnapshot.decode(data)
        #expect(decoded == snapshot)
        #expect(decoded.entries.map(\.recurrence.rule) == [.daily, .weekly(weekdays: [2, 4, 6]), .monthly(day: 25)])
    }

    @Test func emptySnapshotHasNothingPending() {
        let empty = RecurringSnapshot(generatedAt: Date(timeIntervalSince1970: 0), entries: [])
        #expect(empty.pending(on: day(2026, 10, 19)).isEmpty)
    }
}
