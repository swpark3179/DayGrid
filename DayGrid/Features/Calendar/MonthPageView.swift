import DayGridCore
import SwiftData
import SwiftUI
import TipKit

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
    /// 꾹 누르는 중인 날짜(기간 고르기가 시작되기 전). 숫자 둘레에 링이 찬다.
    @State private var chargingDay: LocalDate?
    /// 기간을 고르는 손가락의 위치. 그 위에 기간 문구를 띄운다.
    @State private var pressLocation: CGPoint?
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
                        charging: chargingDay,
                        landing: dropState.landing,
                        onSelectDay: onSelectDay
                    )
                    .frame(height: rowHeight)
                }
            }
            .background(CalendarPageAnchor(visibleDays: visibleDays, onPage: onPage).allowsHitTesting(false))
            .overlay(alignment: .topLeading) {
                if let pressLocation, let rangeStart, let rangeEnd {
                    RangeLabel(text: rangeStart.koreanRangeText(through: rangeEnd))
                        .position(
                            x: min(max(pressLocation.x, RangeLabel.halfWidth), max(RangeLabel.halfWidth, geometry.size.width - RangeLabel.halfWidth)),
                            y: max(pressLocation.y - 56, 16)
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .gesture(RangePressGesture(onPress: handlePressChange) { phase, location in
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
            chargingDay = nil
            // 짧게 누르면 하루 상세. 격자 밖(가장자리 너머)은 무시한다.
            if let day = MonthLayout.day(atX: location.x, y: location.y, width: size.width, height: size.height, in: visibleDays) {
                onSelectDay(day)
            }
        case .began:
            chargingDay = nil
            rangeStart = date
            rangeEnd = date
            pressLocation = location
            RangePressTip().invalidate(reason: .actionPerformed)
        case .changed:
            pressLocation = location
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
            pressLocation = nil
        case .cancelled:
            rangeStart = nil
            rangeEnd = nil
            pressLocation = nil
        }
    }

    /// 손가락이 닿으면(창 좌표) 그 날짜에 링을 채우기 시작하고, 떼거나 달을 넘기면 지운다.
    /// 날짜는 끌어 놓기와 같이 `CalendarDropState`가 이 페이지의 `CalendarPageAnchor`로 찾는다.
    private func handlePressChange(_ windowPoint: CGPoint?) {
        guard let windowPoint, rangeStart == nil else {
            chargingDay = nil
            return
        }
        chargingDay = dropState.day(atWindowPoint: windowPoint)?.day
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

/// 꾹 눌러 끄는 동안 손가락 위에 뜨는 기간 문구. 예: "10월 12일 – 16일 · 5일"
private struct RangeLabel: View {
    /// 화면 가장자리에서 잘리지 않게 가운데를 이만큼 안쪽에 둔다(가장 긴 문구의 반쯤).
    static let halfWidth: CGFloat = 96

    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.82), in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            .accessibilityHidden(true)
    }
}
