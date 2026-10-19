import DayGridCore
import SwiftUI

/// 첫 화면. 좌우로 넘기는 월간 달력.
struct CalendarTab: View {
    let today: LocalDate

    @AppStorage(AppSettings.firstWeekdayKey) private var firstWeekday = 1
    @State private var selectedMonth: Int

    /// 오늘 기준 앞뒤로 넘길 수 있는 달 수.
    private static let monthsAroundToday = 120

    init(today: LocalDate) {
        self.today = today
        _selectedMonth = State(initialValue: today.monthIndex)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                WeekdayHeader(firstWeekday: firstWeekday)
                TabView(selection: $selectedMonth) {
                    ForEach(monthRange, id: \.self) { index in
                        MonthPageView(
                            month: LocalDate(firstDayOfMonthIndex: index),
                            today: today,
                            firstWeekday: firstWeekday
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var monthRange: ClosedRange<Int> {
        (today.monthIndex - Self.monthsAroundToday)...(today.monthIndex + Self.monthsAroundToday)
    }

    private var header: some View {
        HStack {
            Text(LocalDate(firstDayOfMonthIndex: selectedMonth).koreanMonthTitle)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("오늘") {
                withAnimation {
                    selectedMonth = today.monthIndex
                }
            }
            .buttonStyle(.bordered)
            .disabled(selectedMonth == today.monthIndex)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// 일 월 화 … 요일 이름 줄.
struct WeekdayHeader: View {
    let firstWeekday: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                let weekday = (startWeekday - 1 + offset) % 7 + 1
                Text(LocalDate.koreanWeekdaySymbols[weekday - 1])
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DayStyle.color(forWeekday: weekday))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    private var startWeekday: Int {
        (1...7).contains(firstWeekday) ? firstWeekday : 1
    }
}

enum DayStyle {
    /// 일요일은 빨강, 토요일은 파랑.
    static func color(forWeekday weekday: Int) -> Color {
        switch weekday {
        case 1: .red
        case 7: .blue
        default: .primary
        }
    }
}
