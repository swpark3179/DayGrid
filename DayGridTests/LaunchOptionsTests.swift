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
