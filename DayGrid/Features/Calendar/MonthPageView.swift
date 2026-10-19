import DayGridCore
import SwiftData
import SwiftUI

/// 달력 한 달 페이지. 그 달에 보이는 날짜 범위의 일정만 가져와서 배치한다.
struct MonthPageView: View {
    let month: LocalDate
    let today: LocalDate
    let firstWeekday: Int
    let onSelectDay: (LocalDate) -> Void
    let onAddItem: (LocalDate) -> Void

    @Environment(HolidayService.self) private var holidayService
    @Query private var items: [Item]
    @Query private var personalHolidays: [PersonalHoliday]
    @Query private var people: [Person]

    init(
        month: LocalDate,
        today: LocalDate,
        firstWeekday: Int,
        onSelectDay: @escaping (LocalDate) -> Void,
        onAddItem: @escaping (LocalDate) -> Void
    ) {
        self.month = month
        self.today = today
        self.firstWeekday = firstWeekday
        self.onSelectDay = onSelectDay
        self.onAddItem = onAddItem
        let visibleDays = MonthLayout.visibleDays(of: month, firstWeekday: firstWeekday)
        _items = Query(filter: Item.predicate(overlapping: visibleDays), sort: \Item.startDayKey)
        _personalHolidays = Query(filter: PersonalHoliday.predicate(overlapping: visibleDays))
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
            let marks = dayMarks

            VStack(spacing: 0) {
                ForEach(grid.weeks) { week in
                    WeekRowView(
                        week: week,
                        today: today,
                        laneLimit: laneLimit,
                        itemsByID: itemsByID,
                        marks: marks,
                        onSelectDay: onSelectDay,
                        onAddItem: onAddItem
                    )
                    .frame(height: rowHeight)
                }
            }
        }
    }

    /// 보이는 날짜의 공휴일, 개인 휴일, 생일.
    private var dayMarks: [LocalDate: DayMark] {
        let visibleDays = MonthLayout.visibleDays(of: month, firstWeekday: firstWeekday)
        return DayMarks.make(
            in: visibleDays,
            holidays: holidayService.holidays(in: visibleDays),
            personalHolidays: personalHolidays.compactMap { $0.mark },
            birthdays: people.map { (name: $0.name, birthday: $0.birthday) }
        )
    }
}
