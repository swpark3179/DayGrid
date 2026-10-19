import DayGridCore
import SwiftUI

/// 달력의 한 주. 날짜 숫자 아래에 일정 조각을 레인별로 겹쳐 그린다.
struct WeekRowView: View {
    let week: MonthGrid.Week
    let today: LocalDate
    let laneLimit: Int
    let itemsByID: [UUID: Item]
    var onSelectDay: (LocalDate) -> Void = { _ in }
    var onAddItem: (LocalDate) -> Void = { _ in }

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
                        DayNumberView(day: day, isToday: day.date == today)
                            .frame(width: columnWidth, height: geometry.size.height, alignment: .top)
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

                // 맨 위에 날짜별 버튼을 깐다. 탭하면 하루 상세, 길게 누르면 메뉴로 바로 추가.
                HStack(spacing: 0) {
                    ForEach(week.days) { day in
                        DayHitTarget(date: day.date, onSelect: onSelectDay, onAdd: onAddItem)
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
    let onSelect: (LocalDate) -> Void
    let onAdd: (LocalDate) -> Void

    var body: some View {
        Button {
            onSelect(date)
        } label: {
            Color.clear
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("이 날에 일정 추가", systemImage: "plus") {
                onAdd(date)
            }
            Button("이 날 보기", systemImage: "calendar") {
                onSelect(date)
            }
        }
        .accessibilityLabel(date.koreanMonthDayWeekdayText)
        .accessibilityIdentifier("calendar.day.\(date.iso8601)")
    }
}

private struct DayNumberView: View {
    let day: MonthGrid.Day
    let isToday: Bool

    var body: some View {
        Text("\(day.date.day)")
            .font(.system(size: 13, weight: isToday ? .bold : .medium))
            .foregroundStyle(foreground)
            .frame(width: 22, height: 22)
            .background {
                if isToday {
                    Circle().fill(Color.accentColor)
                }
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity)
    }

    private var foreground: Color {
        if isToday { return .white }
        let color = DayStyle.color(forWeekday: day.date.weekday)
        return day.isInMonth ? color : color.opacity(0.35)
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
