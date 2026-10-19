import DayGridCore
import SwiftData
import SwiftUI

/// 달력 한 달 페이지. 그 달에 보이는 날짜 범위의 일정만 가져와서 배치한다.
struct MonthPageView: View {
    let month: LocalDate
    let today: LocalDate
    let firstWeekday: Int

    @Query private var items: [Item]

    init(month: LocalDate, today: LocalDate, firstWeekday: Int) {
        self.month = month
        self.today = today
        self.firstWeekday = firstWeekday
        let visibleDays = MonthLayout.visibleDays(of: month, firstWeekday: firstWeekday)
        _items = Query(filter: Item.predicate(overlapping: visibleDays), sort: \Item.startDayKey)
    }

    var body: some View {
        GeometryReader { geometry in
            let weekCount = max(1, MonthLayout.visibleDays(of: month, firstWeekday: firstWeekday).count / 7)
            let rowHeight = geometry.size.height / CGFloat(weekCount)
            let laneLimit = WeekRowView.visibleLaneCount(rowHeight: rowHeight)
            let grid = MonthLayout.make(
                month: month,
                firstWeekday: firstWeekday,
                entries: items.compactMap { $0.calendarEntry() },
                maxVisibleLanes: laneLimit
            )
            let itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            VStack(spacing: 0) {
                ForEach(grid.weeks) { week in
                    WeekRowView(week: week, today: today, laneLimit: laneLimit, itemsByID: itemsByID)
                        .frame(height: rowHeight)
                }
            }
        }
    }
}
