import DayGridCore
import SwiftUI

/// 달력의 한 주. 날짜 숫자 아래에 일정 조각을 레인별로 겹쳐 그린다.
struct WeekRowView: View {
    let week: MonthGrid.Week
    let today: LocalDate
    let laneLimit: Int
    let itemsByID: [UUID: Item]
    var marks: [LocalDate: DayMark] = [:]
    /// 강조할 날짜(꾹 눌러 고르는 기간, "나중에" 항목을 놓으려는 날)
    var highlighted: ClosedRange<LocalDate>?
    var onSelectDay: (LocalDate) -> Void = { _ in }

    static let dayNumberHeight: CGFloat = 26
    static let laneHeight: CGFloat = 16
    static let laneSpacing: CGFloat = 2
    static var lanePitch: CGFloat { laneHeight + laneSpacing }

    /// 행 높이에 들어가는 일정 줄 수(최소 1).
    static func visibleLaneCount(rowHeight: CGFloat) -> Int {
        max(1, Int((rowHeight - dayNumberHeight - laneSpacing) / lanePitch))
    }

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = geometry.size.width / 7
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(week.days) { day in
                        DayNumberView(day: day, isToday: day.date == today, mark: marks[day.date])
                            .frame(width: columnWidth, height: geometry.size.height, alignment: .top)
                            .background {
                                if highlighted?.contains(day.date) == true {
                                    Rectangle().fill(Color.accentColor.opacity(0.18))
                                }
                            }
                    }
                }

                ForEach(week.segments) { segment in
                    if let item = itemsByID[segment.entryID] {
                        let leadingInset: CGFloat = segment.continuesFromPreviousWeek ? 0 : 2
                        let trailingInset: CGFloat = segment.continuesToNextWeek ? 0 : 2
                        EntryView(segment: segment, item: item)
                            .frame(
                                width: max(0, CGFloat(segment.length) * columnWidth - leadingInset - trailingInset),
                                height: Self.laneHeight
                            )
                            .offset(
                                x: CGFloat(segment.startColumn) * columnWidth + leadingInset,
                                y: Self.dayNumberHeight + CGFloat(segment.lane) * Self.lanePitch
                            )
                    }
                }

                ForEach(0..<7, id: \.self) { column in
                    let hiddenCount = week.days[column].hiddenCount
                    if hiddenCount > 0 {
                        Text("+\(hiddenCount)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                            .frame(width: max(0, columnWidth - 4), height: Self.laneHeight, alignment: .leading)
                            .offset(
                                x: CGFloat(column) * columnWidth + 2,
                                y: Self.dayNumberHeight + CGFloat(laneLimit - 1) * Self.lanePitch
                            )
                    }
                }

                // 맨 위에 날짜별 버튼을 깐다. 탭하면 하루 상세. 꾹 누르기는 달력 페이지(`RangePressGesture`)가 맡는다.
                HStack(spacing: 0) {
                    ForEach(week.days) { day in
                        DayHitTarget(date: day.date, mark: marks[day.date], onSelect: onSelectDay)
                            .frame(width: columnWidth, height: geometry.size.height)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            Divider()
        }
        .clipped()
    }
}

private struct DayHitTarget: View {
    let date: LocalDate
    let mark: DayMark?
    let onSelect: (LocalDate) -> Void

    var body: some View {
        Button {
            onSelect(date)
        } label: {
            Color.clear
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("꾹 누르면 새 일정, 꾹 누른 채 끌면 기간 일정")
        .accessibilityIdentifier("calendar.day.\(date.iso8601)")
    }

    private var accessibilityText: String {
        guard let spoken = mark?.spokenDescription else { return date.koreanMonthDayWeekdayText }
        return "\(date.koreanMonthDayWeekdayText), \(spoken)"
    }
}

/// 날짜 숫자. 공휴일이면 빨갛게, 개인 휴일이면 주황으로 하고, 옆에 이름이나 🎂를 작게 붙인다.
private struct DayNumberView: View {
    let day: MonthGrid.Day
    let isToday: Bool
    let mark: DayMark?

    var body: some View {
        HStack(spacing: 1) {
            Text("\(day.date.day)")
                .font(.system(size: 13, weight: isToday ? .bold : .medium))
                .foregroundStyle(numberColor)
                .frame(width: 22, height: 22)
                .background {
                    if isToday {
                        Circle().fill(Color.accentColor)
                    }
                }
            if let label = mark?.calendarLabel {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(dimmed(labelColor))
                    .lineLimit(1)
            }
        }
        .padding(.top, 2)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
    }

    private var numberColor: Color {
        if isToday { return .white }
        return dimmed(DayStyle.numberColor(for: day.date, mark: mark))
    }

    /// 이름 글자 색. 휴일이 아니면(생일·반복 할일 표시만 있으면) 회색이다.
    private var labelColor: Color {
        if mark?.isPublicHoliday == true { return DayStyle.publicHolidayColor }
        if mark?.isPersonalHoliday == true { return DayStyle.personalHolidayColor }
        return .secondary
    }

    private func dimmed(_ color: Color) -> Color {
        day.isInMonth ? color : color.opacity(0.35)
    }
}

/// 일정 조각 하나. 막대는 카테고리 색으로 채우고, 칩은 색 점과 제목만 그린다.
private struct EntryView: View {
    let segment: MonthGrid.Segment
    let item: Item

    var body: some View {
        switch segment.style {
        case .bar:
            Text(item.title)
                .font(.system(size: 11, weight: .semibold))
                .strikethrough(item.isCompleted)
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: segment.continuesFromPreviousWeek ? 0 : 4,
                        bottomLeadingRadius: segment.continuesFromPreviousWeek ? 0 : 4,
                        bottomTrailingRadius: segment.continuesToNextWeek ? 0 : 4,
                        topTrailingRadius: segment.continuesToNextWeek ? 0 : 4
                    )
                    .fill(color)
                )
        case .chip:
            HStack(spacing: 3) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(item.title)
                    .font(.system(size: 11))
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                    .lineLimit(1)
            }
            .padding(.leading, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var color: Color {
        Color(hex: item.category?.colorHex ?? CategoryPalette.uncategorizedHex)
    }
}
