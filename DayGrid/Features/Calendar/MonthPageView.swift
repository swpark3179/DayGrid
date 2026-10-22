import DayGridCore
import SwiftData
import SwiftUI

/// 달력 한 달 페이지. 그 달에 보이는 날짜 범위의 일정만 가져와서 배치한다.
///
/// - 날짜를 누르면 하루 상세가 열린다.
/// - 꾹 누른 채 다른 날짜까지 끌면 그 기간의 새 일정을 만든다. 움직이지 않고 놓으면 그 날 새 일정이다.
/// - 하루 상세에서 꾹 눌러 옮기거나 "나중에" 항목을 꾹 눌러 넣을 때는 격자 뒤의 `CalendarPageAnchor`로 손가락 아래 날짜를 찾는다.
///   가장자리에 머무르면 `onPage`로 이전·다음 달로 넘긴다.
struct MonthPageView: View {
    let month: LocalDate
    let today: LocalDate
    let firstWeekday: Int
    let onSelectDay: (LocalDate) -> Void
    let onAddItem: (LocalDate) -> Void
    let onAddRange: (LocalDate, LocalDate) -> Void
    let onPage: @MainActor (Int) -> Void

    @Environment(HolidayService.self) private var holidayService
    @Query private var items: [Item]
    @Query private var personalHolidays: [PersonalHoliday]
    @Query private var people: [Person]
    @State private var rangeStart: LocalDate?
    @State private var rangeEnd: LocalDate?
    private let dropState = CalendarDropState.shared

    init(
        month: LocalDate,
        today: LocalDate,
        firstWeekday: Int,
        onSelectDay: @escaping (LocalDate) -> Void,
        onAddItem: @escaping (LocalDate) -> Void,
        onAddRange: @escaping (LocalDate, LocalDate) -> Void = { _, _ in },
        onPage: @escaping @MainActor (Int) -> Void = { _ in }
    ) {
        self.month = month
        self.today = today
        self.firstWeekday = firstWeekday
        self.onSelectDay = onSelectDay
        self.onAddItem = onAddItem
        self.onAddRange = onAddRange
        self.onPage = onPage
        let visibleDays = MonthLayout.visibleDays(of: month, firstWeekday: firstWeekday)
        _items = Query(filter: Item.predicate(overlapping: visibleDays), sort: \Item.startDayKey)
        _personalHolidays = Query(filter: PersonalHoliday.predicate(overlapping: visibleDays))
    }

    var body: some View {
        GeometryReader { geometry in
            let visibleDays = MonthLayout.visibleDays(of: month, firstWeekday: firstWeekday)
            let weekCount = max(1, visibleDays.count / 7)
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
                        highlighted: highlighted(in: visibleDays),
                        onSelectDay: onSelectDay
                    )
                    .frame(height: rowHeight)
                }
            }
            .background(CalendarPageAnchor(visibleDays: visibleDays, onPage: onPage).allowsHitTesting(false))
            .contentShape(Rectangle())
            .gesture(RangePressGesture { phase, location in
                handleRangePress(phase, at: location, size: geometry.size, visibleDays: visibleDays)
            })
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: rangeStart) { _, new in new != nil }
        .sensoryFeedback(.selection, trigger: rangeEnd) { old, new in old != nil && new != nil }
    }

    /// 강조할 날짜: 꾹 눌러 고르는 기간, 아니면 끌어 온 일정을 놓으려는 날.
    private func highlighted(in visibleDays: ClosedRange<LocalDate>) -> ClosedRange<LocalDate>? {
        if let rangeStart, let rangeEnd {
            return min(rangeStart, rangeEnd)...max(rangeStart, rangeEnd)
        }
        if let target = dropState.target, visibleDays.contains(target) {
            return target...target
        }
        return nil
    }

    private func handleRangePress(_ phase: RangePressGesture.Phase, at location: CGPoint, size: CGSize, visibleDays: ClosedRange<LocalDate>) {
        let date = MonthLayout.day(
            atX: location.x,
            y: location.y,
            width: size.width,
            height: size.height,
            in: visibleDays,
            clamped: true
        )
        switch phase {
        case .tap:
            // 짧게 누르면 하루 상세. 격자 밖(가장자리 너머)은 무시한다.
            if let day = MonthLayout.day(atX: location.x, y: location.y, width: size.width, height: size.height, in: visibleDays) {
                onSelectDay(day)
            }
        case .began:
            rangeStart = date
            rangeEnd = date
        case .changed:
            if let date, date != rangeEnd {
                rangeEnd = date
            }
        case .ended:
            if let start = rangeStart {
                let end = date ?? rangeEnd ?? start
                if start == end {
                    onAddItem(start)
                } else {
                    onAddRange(min(start, end), max(start, end))
                }
            }
            rangeStart = nil
            rangeEnd = nil
        case .cancelled:
            rangeStart = nil
            rangeEnd = nil
        }
    }

    /// 보이는 날짜의 공휴일, 개인 휴일, 생일. 반복 할일은 달력에 보이지 않는다(반복 탭에서만 다룬다).
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
