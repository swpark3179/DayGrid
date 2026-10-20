import DayGridCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// 달력 한 달 페이지. 그 달에 보이는 날짜 범위의 일정만 가져와서 배치한다.
///
/// - 날짜를 누르면 하루 상세가 열린다.
/// - 꾹 누른 채 다른 날짜까지 끌면 그 기간의 새 일정을 만든다. 움직이지 않고 놓으면 그 날 새 일정이다.
/// - "나중에" 항목을 끌어 와 놓으면 그 날로 들어간다. 가장자리에 머무르면 이전·다음 달로 넘어간다.
struct MonthPageView: View {
    let month: LocalDate
    let today: LocalDate
    let firstWeekday: Int
    let onSelectDay: (LocalDate) -> Void
    let onAddItem: (LocalDate) -> Void
    let onAddRange: (LocalDate, LocalDate) -> Void
    let onPage: @MainActor (Int) -> Void
    let onDropItem: (UUID, LocalDate) -> Void

    @Environment(HolidayService.self) private var holidayService
    @Query private var items: [Item]
    @Query private var personalHolidays: [PersonalHoliday]
    @Query private var people: [Person]
    @Query private var recurringCompletions: [RecurrenceCompletion]
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
        onPage: @escaping @MainActor (Int) -> Void = { _ in },
        onDropItem: @escaping (UUID, LocalDate) -> Void = { _, _ in }
    ) {
        self.month = month
        self.today = today
        self.firstWeekday = firstWeekday
        self.onSelectDay = onSelectDay
        self.onAddItem = onAddItem
        self.onAddRange = onAddRange
        self.onPage = onPage
        self.onDropItem = onDropItem
        let visibleDays = MonthLayout.visibleDays(of: month, firstWeekday: firstWeekday)
        _items = Query(filter: Item.predicate(overlapping: visibleDays), sort: \Item.startDayKey)
        _personalHolidays = Query(filter: PersonalHoliday.predicate(overlapping: visibleDays))
        let lower = visibleDays.lowerBound.yyyymmdd
        let upper = visibleDays.upperBound.yyyymmdd
        _recurringCompletions = Query(filter: #Predicate<RecurrenceCompletion> { completion in
            completion.completedDayKey >= lower && completion.completedDayKey <= upper
        })
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
            .contentShape(Rectangle())
            .gesture(RangePressGesture { phase, location in
                handleRangePress(phase, at: location, size: geometry.size, visibleDays: visibleDays)
            })
            .onDrop(
                of: [InboxDragPayload.type],
                delegate: CalendarDropDelegate(
                    size: geometry.size,
                    visibleDays: visibleDays,
                    state: dropState,
                    onPage: onPage,
                    onDrop: onDropItem
                )
            )
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: rangeStart) { _, new in new != nil }
        .sensoryFeedback(.selection, trigger: rangeEnd) { old, new in old != nil && new != nil }
    }

    /// 강조할 날짜: 꾹 눌러 고르는 기간, 아니면 "나중에" 항목을 놓으려는 날.
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

    /// 보이는 날짜의 공휴일, 개인 휴일, 생일.
    private var dayMarks: [LocalDate: DayMark] {
        let visibleDays = MonthLayout.visibleDays(of: month, firstWeekday: firstWeekday)
        return DayMarks.make(
            in: visibleDays,
            holidays: holidayService.holidays(in: visibleDays),
            personalHolidays: personalHolidays.compactMap { $0.mark },
            birthdays: people.map { (name: $0.name, birthday: $0.birthday) },
            recurringCompletions: recurringCompletions.compactMap { LocalDate(yyyymmdd: $0.completedDayKey) }
        )
    }
}
