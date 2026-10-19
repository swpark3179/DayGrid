import SwiftData
import SwiftUI

@main
struct DayGridApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let launchOptions: LaunchOptions
    private let modelContainer: ModelContainer
    @State private var clock: AppClock
    @State private var holidays: HolidayService

    init() {
        let options = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
        launchOptions = options
        modelContainer = AppModelContainer.make(options: options)
        _clock = State(initialValue: AppClock(fixedToday: options.fixedToday))
        // UI 테스트는 같은 화면이 나오도록 앱에 넣은 공휴일 자료만 쓴다.
        _holidays = State(initialValue: HolidayService(allowsRemoteUpdate: !options.seedSampleData))
        if let quickAction = options.quickAction {
            QuickActionCenter.shared.pending = quickAction
        }
        NotificationScheduler.shared.container = modelContainer
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(clock)
                .environment(holidays)
                .preferredColorScheme(launchOptions.forcesDarkAppearance ? .dark : nil)
        }
        .modelContainer(modelContainer)
        // 하루 한 번 알림을 다시 맞춘다(앞으로 30일치만 예약해 두므로).
        .backgroundTask(.appRefresh(NotificationScheduler.refreshTaskID)) {
            await NotificationScheduler.shared.sync()
            await NotificationScheduler.shared.scheduleBackgroundRefresh()
        }
    }
}
