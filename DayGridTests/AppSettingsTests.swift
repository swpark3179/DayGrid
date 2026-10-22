import DayGridCore
import Foundation
import Testing
import UIKit
@testable import DayGrid

struct AppSettingsTests {
    /// UI 테스트가 `-appearance dark`로 넘기는 값과 설정 화면의 순서
    @Test func appearanceValues() {
        #expect(AppAppearance.allCases == [.system, .light, .dark])
        #expect(AppAppearance.allCases.map(\.rawValue) == ["system", "light", "dark"])
        #expect(AppAppearance.allCases.map(\.title) == ["시스템", "라이트", "다크"])
        #expect(AppAppearance(rawValue: "sepia") == nil, "모르는 값이면 @AppStorage가 기본값(시스템)을 쓴다")
    }

    @Test func appearanceSetsTheWindowStyle() {
        #expect(AppAppearance.system.userInterfaceStyle == .unspecified)
        #expect(AppAppearance.light.userInterfaceStyle == .light)
        #expect(AppAppearance.dark.userInterfaceStyle == .dark)
    }
}

/// 알림을 누르면 열 곳. 반복 할일은 달력에 보이지 않으므로 반복 탭을 연다.
@MainActor
struct NotificationRouterTests {
    private let day = LocalDate(year: 2026, month: 10, day: 19)!

    @Test func recurringReminderOpensTheRecurringTab() {
        let router = NotificationRouter()
        router.open(day: day, recurringTaskID: UUID())
        #expect(router.routeToOpen == .recurring)
        #expect(router.dayToOpen == nil)
    }

    @Test func otherRemindersOpenTheDay() {
        let router = NotificationRouter()
        router.open(day: day, recurringTaskID: nil)
        #expect(router.dayToOpen == day)
        #expect(router.routeToOpen == nil)
    }
}
