import DayGridCore
import Foundation
import Testing
@testable import DayGrid

@MainActor
struct CalendarDropStateTests {
    private let start = Date(timeIntervalSince1970: 1_792_400_000)

    @Test func theDraggedItemIsTakenOnlyOnce() {
        let state = CalendarDropState()
        let id = UUID()
        state.begin(itemID: id, now: start)
        #expect(state.takeItemID(now: start.addingTimeInterval(3)) == id)
        #expect(state.takeItemID(now: start.addingTimeInterval(4)) == nil, "한 번 놓으면 비운다")
    }

    @Test func anOldCancelledDragIsIgnored() {
        let state = CalendarDropState()
        state.begin(itemID: UUID(), now: start)
        #expect(state.takeItemID(now: start.addingTimeInterval(301)) == nil)
    }

    @Test func endingTheHoverClearsTheTarget() {
        let state = CalendarDropState()
        state.target = LocalDate(year: 2026, month: 10, day: 22)
        state.endHover()
        #expect(state.target == nil)
    }
}
