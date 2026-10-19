import DayGridCore
import SwiftUI

@main
struct DayGridApp: App {
    private let launchOptions = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)

    var body: some Scene {
        WindowGroup {
            RootView(today: launchOptions.fixedToday ?? LocalDate.today())
        }
    }
}
