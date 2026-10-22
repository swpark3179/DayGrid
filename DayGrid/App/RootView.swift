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
    @State private var monthToShow: LocalDate?
    @Query(filter: RecurringTask.activePredicate) private var activeRecurringTasks: [RecurringTask]

    /// 주기가 돌아왔는데 아직 하지 않은 반복 할일 수. 0이면 배지를 보이지 않는다.
    private var dueRecurringCount: Int {
        activeRecurringTasks.filter { $0.isDue(on: clock.today) }.count
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("달력", systemImage: "calendar", value: AppTab.calendar) {
                CalendarTab(today: clock.today, dayToOpen: $dayToOpen, monthToShow: $monthToShow)
            }
            Tab("나중에", systemImage: "tray", value: AppTab.inbox) {
                // 꾹 눌러 달력에 넣으면 달력 탭에서 그 달을 보여준다(사용자 결정 2026-10-21).
                InboxTab(focusRequest: inboxFocusRequest) { day in
                    monthToShow = day
                    selectedTab = .calendar
                }
            }
            Tab("반복", systemImage: "repeat", value: AppTab.recurring) {
                RecurringTab()
            }
            .badge(dueRecurringCount)
            Tab("설정", systemImage: "gearshape", value: AppTab.settings) {
                SettingsTab()
            }
        }
        .task {
            WidgetSnapshotWriter.shared.write()
            await holidays.refreshIfNeeded()
            await NotificationScheduler.shared.sync()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                clock.refresh()
                Task { await holidays.refreshIfNeeded() }
                NotificationScheduler.shared.scheduleSync(after: .zero)
                WidgetSnapshotWriter.shared.write()
            case .background:
                NotificationScheduler.shared.scheduleBackgroundRefresh()
            default:
                break
            }
        }
        // 일정·생일·반복 할일이 바뀌면 알림을 다시 맞춘다.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: DispatchQueue.main)) { _ in
            NotificationScheduler.shared.scheduleSync()
            WidgetSnapshotWriter.shared.scheduleWrite()
        }
        // 잠금화면 위젯을 누르면 반복 탭을 연다.
        .onOpenURL { url in
            if let route = AppRoute(url: url) {
                show(route)
            }
        }
        // 반복 할일 알림을 누르면 반복 탭을 연다.
        .onChange(of: NotificationRouter.shared.routeToOpen, initial: true) { _, route in
            guard let route else { return }
            NotificationRouter.shared.routeToOpen = nil
            show(route)
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

    private func show(_ route: AppRoute) {
        switch route {
        case .recurring:
            selectedTab = .recurring
        }
    }
}
