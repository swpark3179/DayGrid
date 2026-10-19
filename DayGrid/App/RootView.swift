import Combine
import DayGridCore
import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case calendar
    case inbox
    case recurring
    case settings
}

struct RootView: View {
    @Environment(AppClock.self) private var clock
    @Environment(HolidayService.self) private var holidays
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .calendar
    @State private var inboxFocusRequest = 0
    @State private var dayToOpen: LocalDate?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("달력", systemImage: "calendar", value: AppTab.calendar) {
                CalendarTab(today: clock.today, dayToOpen: $dayToOpen)
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
        .task {
            await holidays.refreshIfNeeded()
            await NotificationScheduler.shared.sync()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                clock.refresh()
                Task { await holidays.refreshIfNeeded() }
                NotificationScheduler.shared.scheduleSync(after: .zero)
            case .background:
                NotificationScheduler.shared.scheduleBackgroundRefresh()
            default:
                break
            }
        }
        // 일정·생일·반복 할일이 바뀌면 알림을 다시 맞춘다.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: DispatchQueue.main)) { _ in
            NotificationScheduler.shared.scheduleSync()
        }
        .onChange(of: NotificationRouter.shared.dayToOpen, initial: true) { _, day in
            guard let day else { return }
            NotificationRouter.shared.dayToOpen = nil
            selectedTab = .calendar
            dayToOpen = day
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
