import DayGridCore
import Observation
import UIKit
import UserNotifications

/// 홈 화면 아이콘을 길게 누르면 나오는 퀵 액션.
enum QuickAction: String, CaseIterable {
    /// "나중에" 탭을 열고 빠른 입력창에 바로 쓰게 한다.
    case addTask

    var title: String {
        switch self {
        case .addTask: "할일 빠르게 추가"
        }
    }

    var systemImage: String {
        switch self {
        case .addTask: "plus.circle"
        }
    }
}

/// 아직 처리하지 않은 퀵 액션. 앱(씬) 델리게이트가 넣고, `RootView`가 처리한 뒤 비운다.
@MainActor
@Observable
final class QuickActionCenter {
    static let shared = QuickActionCenter()

    var pending: QuickAction?
}

/// 퀵 액션 목록을 등록하고, 퀵 액션으로 앱이 처음 열릴 때 그 동작을 받는다.
/// 알림 센터의 델리게이트도 맡는다(앱을 쓰는 중에도 배너를 보이고, 알림의 "완료"와 탭을 처리한다).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationScheduler.shared.registerCategories()
        application.shortcutItems = QuickAction.allCases.map { action in
            UIApplicationShortcutItem(
                type: action.rawValue,
                localizedTitle: action.title,
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: action.systemImage)
            )
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let shortcutItem = options.shortcutItem {
            QuickActionCenter.shared.pending = QuickAction(rawValue: shortcutItem.type)
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        // 알림 정보는 보내기 전에 문자열로 꺼낸다(UNNotificationResponse는 다른 액터로 넘길 수 없다).
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let day = (info[NotificationScheduler.UserInfoKey.day] as? String).flatMap { LocalDate(iso8601: $0) }
        let itemID = (info[NotificationScheduler.UserInfoKey.itemID] as? String).flatMap { UUID(uuidString: $0) }
        let taskID = (info[NotificationScheduler.UserInfoKey.taskID] as? String).flatMap { UUID(uuidString: $0) }
        let cycleStart = (info[NotificationScheduler.UserInfoKey.cycleStart] as? String).flatMap { LocalDate(iso8601: $0) }

        await MainActor.run {
            if action == NotificationScheduler.completeAction {
                NotificationScheduler.shared.complete(itemID: itemID, taskID: taskID, cycleStart: cycleStart)
            } else if action == UNNotificationDefaultActionIdentifier {
                NotificationRouter.shared.open(day: day, recurringTaskID: taskID)
            }
        }
    }
}

/// 앱이 이미 떠 있을 때 누른 퀵 액션을 받는다.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        guard let action = QuickAction(rawValue: shortcutItem.type) else { return false }
        QuickActionCenter.shared.pending = action
        return true
    }
}
