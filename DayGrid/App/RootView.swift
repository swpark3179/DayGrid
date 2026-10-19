import DayGridCore
import SwiftUI

enum AppTab: Hashable {
    case calendar
    case inbox
    case recurring
    case settings
}

struct RootView: View {
    let today: LocalDate

    @State private var selectedTab: AppTab = .calendar

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("달력", systemImage: "calendar", value: AppTab.calendar) {
                CalendarTab(today: today)
            }
            Tab("나중에", systemImage: "tray", value: AppTab.inbox) {
                InboxTab()
            }
            Tab("반복", systemImage: "repeat", value: AppTab.recurring) {
                RecurringTab()
            }
            Tab("설정", systemImage: "gearshape", value: AppTab.settings) {
                SettingsTab()
            }
        }
    }
}
