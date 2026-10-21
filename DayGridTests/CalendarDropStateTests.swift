import DayGridCore
import Foundation
import Testing
import UIKit
@testable import DayGrid

/// 꾹 눌러 끄는 동안 창 좌표로 날짜 칸을 찾는 규칙(하루 상세에서 옮기기, "나중에"에서 넣기).
@MainActor
struct CalendarDropStateTests {
    /// 2026년 10월(일요일 시작)은 9/27–10/31, 5주다.
    private let october = MonthLayout.visibleDays(of: LocalDate(year: 2026, month: 10, day: 1)!, firstWeekday: 1)

    private func day(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: year, month: month, day: day)!
    }

    /// 창 안의 350×500 격자. 칸은 가로 50, 세로 100이다.
    private func makeGrid(in container: UIView? = nil) -> (window: UIWindow, grid: UIView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let grid = UIView(frame: CGRect(x: 25, y: 100, width: 350, height: 500))
        if let container {
            window.addSubview(container)
            container.addSubview(grid)
        } else {
            window.addSubview(grid)
        }
        return (window, grid)
    }

    @Test func endingTheHoverClearsTheTarget() {
        let state = CalendarDropState()
        state.target = day(2026, 10, 22)
        state.endHover()
        #expect(state.target == nil)
    }

    @Test func theDayUnderAWindowPointIsFound() {
        let state = CalendarDropState()
        let (window, grid) = makeGrid()
        state.registerPage(grid, visibleDays: october, onPage: { _ in })

        let first = state.day(atWindowPoint: CGPoint(x: 30, y: 150))
        #expect(first?.day == day(2026, 9, 27))
        #expect(first?.edge == -1, "왼쪽 가장자리")

        let middle = state.day(atWindowPoint: CGPoint(x: 200, y: 350))
        #expect(middle?.day == day(2026, 10, 14), "셋째 줄 가운데 칸")
        #expect(middle?.edge == 0)

        let last = state.day(atWindowPoint: CGPoint(x: 370, y: 590))
        #expect(last?.day == day(2026, 10, 31))
        #expect(last?.edge == 1, "오른쪽 가장자리")

        #expect(state.day(atWindowPoint: CGPoint(x: 200, y: 50))?.day == nil, "격자 밖")
        withExtendedLifetime(window) {}
    }

    @Test func aHiddenOrRemovedPageIsNotADropTarget() {
        let state = CalendarDropState()
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let (window, grid) = makeGrid(in: container)
        state.registerPage(grid, visibleDays: october, onPage: { _ in })
        let point = CGPoint(x: 200, y: 350)
        #expect(state.day(atWindowPoint: point)?.day != nil)

        container.isHidden = true
        #expect(state.day(atWindowPoint: point)?.day == nil, "숨긴 달력(예: 다른 탭)에는 놓지 않는다")

        container.isHidden = false
        container.removeFromSuperview()
        #expect(state.day(atWindowPoint: point)?.day == nil, "창에서 빠진 달력에는 놓지 않는다")
        withExtendedLifetime(window) {}
    }

    @Test func dwellingAtTheEdgePagesTheCalendarUnderTheFinger() async throws {
        let state = CalendarDropState()
        let (window, grid) = makeGrid()
        let recorder = PageRecorder()
        state.registerPage(grid, visibleDays: october, onPage: { recorder.deltas.append($0) })

        #expect(state.hover(atWindowPoint: CGPoint(x: 30, y: 350)) == day(2026, 10, 11))
        try await Task.sleep(for: .milliseconds(1200))
        state.endHover()
        #expect(recorder.deltas.first == -1, "왼쪽 가장자리에 머무르면 그 페이지의 달력을 이전 달로 넘긴다")
        withExtendedLifetime(window) {}
    }
}

@MainActor
private final class PageRecorder {
    var deltas: [Int] = []
}
