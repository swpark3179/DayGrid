import DayGridCore
import Foundation
import Observation

/// 앱 전체가 쓰는 "오늘". 날짜가 바뀌거나 앱이 다시 활성화되면 갱신한다.
/// UI 테스트에서 날짜를 고정했으면 바뀌지 않는다.
@MainActor
@Observable
final class AppClock {
    private(set) var today: LocalDate
    private let fixedToday: LocalDate?

    init(fixedToday: LocalDate?) {
        self.fixedToday = fixedToday
        self.today = fixedToday ?? LocalDate.today()
    }

    func refresh() {
        guard fixedToday == nil else { return }
        let now = LocalDate.today()
        if now != today {
            today = now
        }
    }
}
