import DayGridCore
import Testing
@testable import DayGrid

struct LaunchOptionsTests {
    @Test func parsesFixedTodayAndSeedFlag() {
        let options = LaunchOptions(arguments: ["DayGrid", "-UITestFixedToday", "2026-10-19", "-UITestSeedData"])
        #expect(options.fixedToday == LocalDate(year: 2026, month: 10, day: 19))
        #expect(options.seedSampleData)
    }

    @Test func defaultsWhenNoFlags() {
        let options = LaunchOptions(arguments: ["DayGrid"])
        #expect(options.fixedToday == nil)
        #expect(!options.seedSampleData)
        #expect(!options.forcesDarkAppearance)
    }

    @Test func parsesColorScheme() {
        #expect(LaunchOptions(arguments: ["DayGrid", "-UITestColorScheme", "dark"]).forcesDarkAppearance)
        #expect(!LaunchOptions(arguments: ["DayGrid", "-UITestColorScheme", "light"]).forcesDarkAppearance)
        #expect(!LaunchOptions(arguments: ["DayGrid", "-UITestColorScheme"]).forcesDarkAppearance)
    }

    @Test func parsesQuickAction() {
        #expect(LaunchOptions(arguments: ["DayGrid", "-UITestQuickAction", "addTask"]).quickAction == .addTask)
        #expect(LaunchOptions(arguments: ["DayGrid", "-UITestQuickAction", "unknown"]).quickAction == nil)
        #expect(LaunchOptions(arguments: ["DayGrid"]).quickAction == nil)
    }

    @Test(arguments: [
        ["DayGrid", "-UITestFixedToday"],
        ["DayGrid", "-UITestFixedToday", "2026-02-30"],
        ["DayGrid", "-UITestFixedToday", "tomorrow"],
    ])
    func ignoresMissingOrInvalidDate(arguments: [String]) {
        #expect(LaunchOptions(arguments: arguments).fixedToday == nil)
    }
}
