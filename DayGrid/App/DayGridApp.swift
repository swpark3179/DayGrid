import SwiftData
import SwiftUI
import TipKit

@main
struct DayGridApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer
    @State private var clock: AppClock
    @State private var holidays: HolidayService
    @AppStorage(AppSettings.appearanceKey) private var appearance = AppAppearance.system

    init() {
        let options = LaunchOptions(arguments: ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment)
        modelContainer = AppModelContainer.make(options: options)
        _clock = State(initialValue: AppClock(fixedToday: options.fixedToday))
        // UI 테스트는 같은 화면이 나오도록 앱에 넣은 공휴일 자료만 쓴다.
        _holidays = State(initialValue: HolidayService(allowsRemoteUpdate: !options.seedSampleData))
        if let quickAction = options.quickAction {
            QuickActionCenter.shared.pending = quickAction
        }
        NotificationScheduler.shared.container = modelContainer
        WidgetSnapshotWriter.shared.container = modelContainer
        UndoToastState.usesUITestDuration = options.keepsToastsLonger
        Self.configureTips(options)
    }

    /// 꾹 누르기 안내 팁(`GestureTips.swift`). 테스트용 설정은 `configure` 전에 해야 한다.
    private static func configureTips(_ options: LaunchOptions) {
        if options.showsTips {
            // 앞선 테스트가 닫은 팁도 다시 보이게 한다.
            try? Tips.resetDatastore()
            Tips.showAllTipsForTesting()
        } else if options.hidesTips {
            Tips.hideAllTipsForTesting()
        }
        try? Tips.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(clock)
                .environment(holidays)
                .background(WindowAppearance(appearance: appearance))
        }
        .modelContainer(modelContainer)
        // 하루 한 번 알림을 다시 맞춘다(앞으로 30일치만 예약해 두므로).
        .backgroundTask(.appRefresh(NotificationScheduler.refreshTaskID)) {
            await NotificationScheduler.shared.sync()
            await NotificationScheduler.shared.scheduleBackgroundRefresh()
        }
    }
}
