import DayGridCore
import Foundation

/// 앱 밖에서 여는 주소(`daygrid://…`, `Info.plist`의 `CFBundleURLTypes`).
/// 잠금화면 위젯이 `daygrid://recurring`(`RecurringSnapshot.openURL`)으로 반복 탭을 연다.
enum AppRoute: Equatable {
    case recurring

    init?(url: URL) {
        guard url.scheme?.lowercased() == RecurringSnapshot.openURL.scheme else { return nil }
        switch url.host()?.lowercased() {
        case RecurringSnapshot.openURL.host():
            self = .recurring
        default:
            return nil
        }
    }
}
