import DayGridCore
import SwiftUI

/// 달력의 한 주. 날짜 숫자 아래에 일정 조각을 레인별로 겹쳐 그린다.
struct WeekRowView: View {
    let week: MonthGrid.Week
    let today: LocalDate
    let laneLimit: Int
    let itemsByID: [UUID: Item]
    var marks: [LocalDate: DayMark] = [:]
    /// 강조할 날짜(꾹 눌러 고르는 기간, "나중에" 항목을 놓으려는 날). 주 안에서 이어진 둥근 띠 하나로 그린다.
    var highlighted: ClosedRange<LocalDate>?
    /// 꾹 누르는 중인 날짜. 기간 고르기가 시작될 때까지 숫자 둘레에 링이 찬다.
    var charging: LocalDate?
    /// 방금 일정이 들어간 날짜(`CalendarDropState.land`). 한 번 빛나고, 그 일정의 막대가 튀어 들어온다.
    var landing: CalendarLanding?
    var onSelectDay: (LocalDate) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                if let band = DayBand(range: highlighted, in: week) {
                    band.shape
                        .fill(Color.accentColor.opacity(0.14))
                        .overlay(band.shape.stroke(Color.accentColor.opacity(0.6), lineWidth: 1.5))
                        .frame(width: band.width(columnWidth: columnWidth), height: max(0, geometry.size.height - 4))
                        .offset(x: band.x(columnWidth: columnWidth), y: 2)
                        .transition(.opacity)
                        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: highlighted)
                }

                HStack(spacing: 0) {
                    ForEach(week.days) { day in
                        DayNumberView(day: day, isToday: day.date == today, mark: marks[day.date], isCharging: day.date == charging)
                            .frame(width: columnWidth, height: geometry.size.height, alignment: .top)
                    }
                }

                ForEach(week.segments) { segment in
                    if let item = itemsByID[segment.entryID] {
                        let leadingInset: CGFloat = segment.continuesFromPreviousWeek ? 0 : 2
                        let trailingInset: CGFloat = segment.continuesToNextWeek ? 0 : 2
                        EntryView(segment: segment, item: item)
                            .modifier(LandingPop(token: landing?.itemID == segment.entryID ? landing?.id : nil))
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

                if let landing, let band = DayBand(range: landing.days, in: week) {
                    LandingPulse(shape: band.shape)
                        .frame(width: band.width(columnWidth: columnWidth), height: max(0, geometry.size.height - 4))
                        .offset(x: band.x(columnWidth: columnWidth), y: 2)
                        .id(landing.id)
                        .allowsHitTesting(false)
                }

                // 맨 위에 날짜별 접근성 요소를 깐다. 탭과 꾹 누르기는 달력 페이지의 `RangePressGesture` 하나가 받는다.
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

/// 날짜 칸의 접근성 요소(VoiceOver, UI 테스트의 `calendar.day.yyyy-MM-dd` 버튼).
/// `Button`을 쓰지 않는다. SwiftUI는 자식 제스처를 먼저 주므로, 버튼이 누르기를 잡으면 페이지의 꾹 누르기가 시작되지 못한다
/// (PR #15 CI: 꾹 눌러 끌었더니 달이 넘어갔다). 손가락 탭은 `RangePressGesture`가 받아 같은 `onSelect`를 부른다.
private struct DayHitTarget: View {
    let date: LocalDate
    let mark: DayMark?
    let onSelect: (LocalDate) -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onSelect(date) }
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
    var isCharging = false

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
                .overlay {
                    if isCharging {
                        PressChargeRing()
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

/// 강조 범위가 이 주에서 차지하는 열. 범위가 앞뒤 주로 이어지면 그쪽 모서리를 평평하게 두어 띠가 이어져 보이게 한다.
private struct DayBand {
    static let cornerRadius: CGFloat = 10
    static let inset: CGFloat = 2

    let startColumn: Int
    let length: Int
    let continuesFromPreviousWeek: Bool
    let continuesToNextWeek: Bool

    init?(range: ClosedRange<LocalDate>?, in week: MonthGrid.Week) {
        guard let range, let firstDay = week.days.first, let lastDay = week.days.last,
              let first = week.days.firstIndex(where: { range.contains($0.date) }),
              let last = week.days.lastIndex(where: { range.contains($0.date) })
        else { return nil }
        startColumn = first
        length = last - first + 1
        continuesFromPreviousWeek = range.lowerBound < firstDay.date
        continuesToNextWeek = range.upperBound > lastDay.date
    }

    var shape: UnevenRoundedRectangle {
        let leading = continuesFromPreviousWeek ? 0 : Self.cornerRadius
        let trailing = continuesToNextWeek ? 0 : Self.cornerRadius
        return UnevenRoundedRectangle(
            topLeadingRadius: leading,
            bottomLeadingRadius: leading,
            bottomTrailingRadius: trailing,
            topTrailingRadius: trailing
        )
    }

    func x(columnWidth: CGFloat) -> CGFloat {
        CGFloat(startColumn) * columnWidth + (continuesFromPreviousWeek ? 0 : Self.inset)
    }

    func width(columnWidth: CGFloat) -> CGFloat {
        let insets = (continuesFromPreviousWeek ? 0 : Self.inset) + (continuesToNextWeek ? 0 : Self.inset)
        return max(0, CGFloat(length) * columnWidth - insets)
    }
}

/// 꾹 누르는 동안 날짜 숫자 둘레에 차오르는 링. 다 차는 때가 기간 고르기가 시작되는 때다(`DayPressRecognizer.minimumPressDuration`).
/// 달을 넘기려고 스치는 손가락에는 보이지 않도록 조금 늦게 시작한다.
private struct PressChargeRing: View {
    static let delay: TimeInterval = 0.1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var isVisible = false

    var body: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: 28, height: 28)
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(false)
            .onAppear {
                let duration = max(0.05, DayPressRecognizer.minimumPressDuration - Self.delay)
                withAnimation(.easeOut(duration: 0.08).delay(Self.delay)) {
                    isVisible = true
                }
                withAnimation(reduceMotion ? nil : .linear(duration: duration).delay(Self.delay)) {
                    progress = 1
                }
            }
    }
}

/// 일정이 방금 들어간 칸. 한 번 칠했다가 지우고, 테두리가 바깥으로 퍼지며 사라진다. 동작 줄이기면 칠만 한다.
private struct LandingPulse: View {
    let shape: UnevenRoundedRectangle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFaded = false

    var body: some View {
        ZStack {
            shape.fill(Color.accentColor.opacity(isFaded ? 0 : 0.22))
            if !reduceMotion {
                shape.stroke(Color.accentColor, lineWidth: 2)
                    .scaleEffect(isFaded ? 1.08 : 0.98)
                    .opacity(isFaded ? 0 : 1)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.05)) {
                isFaded = true
            }
        }
    }
}

/// 방금 들어간 일정의 막대가 작게 시작해 제자리 크기로 튀어 들어온다. 달 페이지가 나중에 그려져도(탭을 바꾼 뒤) 보이도록
/// 처음 나타날 때도 `token`을 본다.
private struct LandingPop: ViewModifier {
    let token: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popCount = 0

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: CGFloat(1), trigger: popCount) { view, scale in
                view.scaleEffect(scale, anchor: .leading)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(CGFloat(0.6), duration: 0.01)
                    SpringKeyframe(CGFloat(1), duration: 0.4, spring: .snappy(extraBounce: 0.15))
                }
            }
            .onChange(of: token, initial: true) { _, token in
                if token != nil, !reduceMotion {
                    popCount += 1
                }
            }
    }
}
