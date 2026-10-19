import Combine
import SwiftUI

enum AppTab: Hashable {
    case calendar
    case inbox
    case recurring
    case settings
}

struct RootView: View {
    @Environment(AppClock.self) private var clock
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .calendar

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("달력", systemImage: "calendar", value: AppTab.calendar) {
                CalendarTab(today: clock.today)
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                clock.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: DispatchQueue.main)) { _ in
            clock.refresh()
        }
    }
}
