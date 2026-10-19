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
    @State private var inboxFocusRequest = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("달력", systemImage: "calendar", value: AppTab.calendar) {
                CalendarTab(today: clock.today)
            }
            Tab("나중에", systemImage: "tray", value: AppTab.inbox) {
                InboxTab(focusRequest: inboxFocusRequest)
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
        .onChange(of: QuickActionCenter.shared.pending, initial: true) { _, action in
            guard let action else { return }
            QuickActionCenter.shared.pending = nil
            switch action {
            case .addTask:
                selectedTab = .inbox
                inboxFocusRequest += 1
            }
        }
    }
}
