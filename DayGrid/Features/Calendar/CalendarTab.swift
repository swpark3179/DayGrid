import DayGridCore
import SwiftUI

struct CalendarTab: View {
    let today: LocalDate

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("달력 준비 중", systemImage: "calendar")
            } description: {
                Text("오늘은 \(today.koreanLongText)입니다.")
            }
            .navigationTitle(today.koreanMonthTitle)
        }
    }
}
