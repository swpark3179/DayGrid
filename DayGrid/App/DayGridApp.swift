import SwiftData
import SwiftUI

@main
struct DayGridApp: App {
    private let launchOptions: LaunchOptions
    private let modelContainer: ModelContainer
    @State private var clock: AppClock

    init() {
        let options = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
        launchOptions = options
        modelContainer = AppModelContainer.make(options: options)
        _clock = State(initialValue: AppClock(fixedToday: options.fixedToday))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(clock)
                .preferredColorScheme(launchOptions.forcesDarkAppearance ? .dark : nil)
        }
        .modelContainer(modelContainer)
    }
}
