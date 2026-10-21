import DayGridCore
import SwiftUI

/// "나중에" 항목을 꾹 누르는 동안 목록 위에 덮는 달력. 손가락 아래 날짜는 `CalendarDropState`가 페이지의
/// `CalendarPageAnchor`로 찾고, 가장자리에 머무르면 이 달력의 달을 넘긴다.
///
/// - 달력 탭으로 바꾸지 않는 이유: 탭을 바꾸면 누른 행이 창에서 빠져 손가락 추적이 끊긴다(Phase 11 시스템 끌어 놓기가
///   기기에서 놓이지 않던 원인). 덮개 아래의 행이 `WindowPressGesture`로 끝까지 손가락을 따라간다.
/// - 누르기와 접근성은 받지 않는다. 손가락은 이미 행이 잡고 있고, 달력 탭과 같은 `calendar.day.…` 요소가 겹치지 않게 한다.
/// - 날짜 칸이 달력 탭과 거의 같은 자리에 오도록 머리 줄(연·월, 안내)의 높이를 달력 탭의 머리 줄과 비슷하게 둔다.
struct InboxCalendarOverlay: View {
    let today: LocalDate
    @Binding var month: Int

    @AppStorage(AppSettings.firstWeekdayKey) private var firstWeekday = 1

    var body: some View {
        let range = CalendarTab.monthRange(around: today)
        VStack(spacing: 0) {
            HStack {
                Text(LocalDate(firstDayOfMonthIndex: month).koreanMonthTitle)
                    .font(.title2.bold())
                Spacer()
            }
            .frame(minHeight: 34)
            .padding(.horizontal)
            .padding(.vertical, 8)
            Label("넣을 날짜 위에서 손을 떼세요. 달력 밖에서 떼면 취소합니다.", systemImage: "calendar.badge.plus")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 8)
            WeekdayHeader(firstWeekday: firstWeekday)
            TabView(selection: $month) {
                ForEach(range, id: \.self) { index in
                    MonthPageView(
                        month: LocalDate(firstDayOfMonthIndex: index),
                        today: today,
                        firstWeekday: firstWeekday,
                        onSelectDay: { _ in },
                        onAddItem: { _ in },
                        onPage: { delta in
                            let next = month + delta
                            guard range.contains(next) else { return }
                            withAnimation {
                                month = next
                            }
                        }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(.background)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
