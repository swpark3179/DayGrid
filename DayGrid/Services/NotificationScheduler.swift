import BackgroundTasks
import DayGridCore
import Foundation
import Observation
import SwiftData
import UserNotifications

/// 로컬 알림 예약. Core `ReminderPlanner`가 고른 알림(앞으로 30일, 가까운 60개)과
/// 대기 중인 알림을 비교해 바뀐 것만 지우고 더한다.
///
/// 동기화 시점: 앱 실행, 포그라운드 진입, 데이터 저장(1초 모아서), 하루 한 번 백그라운드 새로 고침.
/// 알림 권한은 사용자가 처음 알림을 켤 때만 묻는다. 권한이 없으면 동기화하지 않는다.
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    static let taskCategory = "daygrid.task"
    static let recurringCategory = "daygrid.recurring"
    static let completeAction = "daygrid.complete"
    static let refreshTaskID = "io.github.swpark3179.DayGrid.refresh"

    /// 앱이 만든 저장소. 알림의 "완료" 동작과 백그라운드 동기화에 쓴다.
    var container: ModelContainer?

    private var center: UNUserNotificationCenter { .current() }
    private var pendingSync: Task<Void, Never>?

    func registerCategories() {
        let complete = UNNotificationAction(identifier: Self.completeAction, title: "완료", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.taskCategory, actions: [complete], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.recurringCategory, actions: [complete], intentIdentifiers: []),
        ])
    }

    /// 처음 알림을 켤 때 부른다. 이미 정해졌으면 묻지 않는다.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted {
                await sync()
            }
            return granted
        }
    }

    /// 잠깐 모았다가 한 번만 동기화한다(저장이 연달아 일어날 때).
    func scheduleSync(after delay: Duration = .seconds(1)) {
        pendingSync?.cancel()
        pendingSync = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await sync()
        }
    }

    func sync(now: Date = Date()) async {
        guard let container else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let planned = plan(context: container.mainContext, now: now)
        let wanted = Dictionary(planned.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        let pending = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(ReminderPlanner.identifierPrefix) }

        var kept = Set<String>()
        var stale: [String] = []
        for request in pending {
            if let reminder = wanted[request.identifier], Self.matches(request, reminder) {
                kept.insert(request.identifier)
            } else {
                stale.append(request.identifier)
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        for reminder in planned where !kept.contains(reminder.identifier) {
            try? await center.add(Self.request(for: reminder))
        }
    }

    /// 하루 뒤에 백그라운드 새로 고침을 한 번 더 부탁한다.
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(24 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - 알림 동작

    /// 알림의 "완료" 동작. 할일이면 완료로, 반복 할일이면 그 주기를 완료로 표시한다(이미 완료면 그대로 둔다).
    func complete(itemID: UUID?, taskID: UUID?, cycleStart: LocalDate?) {
        guard let context = container?.mainContext else { return }
        if let itemID {
            var descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
            descriptor.fetchLimit = 1
            if let item = try? context.fetch(descriptor).first, item.isTask, !item.isCompleted {
                item.toggleCompletion()
            }
        }
        if let taskID, let cycleStart {
            var descriptor = FetchDescriptor<RecurringTask>(predicate: #Predicate { $0.id == taskID })
            descriptor.fetchLimit = 1
            if let task = try? context.fetch(descriptor).first,
               task.completionDays[cycleStart] == nil,
               let cycle = task.recurrence?.cycle(containing: cycleStart) {
                task.toggleCompletion(of: cycle, today: LocalDate.today(), in: context)
            }
        }
        try? context.save()
    }

    // MARK: - 계획

    private func plan(context: ModelContext, now: Date) -> [PlannedReminder] {
        let items = (try? context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.reminderMask > 0 && $0.startDayKey > 0 }))) ?? []
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        let tasks = (try? context.fetch(FetchDescriptor<RecurringTask>(predicate: RecurringTask.activePredicate))) ?? []
        let birthdayDays = AppSettings.birthdayReminderDays(
            UserDefaults.standard.object(forKey: AppSettings.birthdayReminderKey) as? Int ?? -1
        )

        return ReminderPlanner.plan(
            items: items.compactMap { item -> ReminderPlanner.ItemInput? in
                guard let startDay = item.calendarEntry()?.startDay else { return nil }
                return ReminderPlanner.ItemInput(
                    id: item.id,
                    title: item.title,
                    isTask: item.isTask,
                    isCompleted: item.isCompleted,
                    isAllDay: item.isAllDay,
                    startDay: startDay,
                    startDate: item.startDate,
                    options: ReminderOption.options(in: item.reminderMask)
                )
            },
            birthdays: people.map { ReminderPlanner.BirthdayInput(id: $0.id, name: $0.name, birthday: $0.birthday) },
            birthdaySettings: ReminderPlanner.BirthdaySettings(daysBefore: birthdayDays),
            recurring: tasks.compactMap { task -> ReminderPlanner.RecurringInput? in
                guard let recurrence = task.recurrence else { return nil }
                return ReminderPlanner.RecurringInput(
                    id: task.id,
                    title: task.title,
                    recurrence: recurrence,
                    notifyMinute: task.notifyMinute,
                    completedCycleStarts: Set(task.completionDays.keys)
                )
            },
            now: now
        )
    }

    private static func request(for reminder: PlannedReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        var info: [String: Any] = [
            UserInfoKey.fireDate: reminder.fireDate.timeIntervalSince1970,
            UserInfoKey.day: reminder.day.iso8601,
        ]
        switch reminder.kind {
        case .item(let id, let isTask):
            info[UserInfoKey.itemID] = id.uuidString
            if isTask {
                content.categoryIdentifier = taskCategory
            }
        case .birthday:
            break
        case .recurring(let taskID, let cycleStart):
            info[UserInfoKey.taskID] = taskID.uuidString
            info[UserInfoKey.cycleStart] = cycleStart.iso8601
            content.categoryIdentifier = recurringCategory
        }
        content.userInfo = info

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
    }

    /// 대기 중인 알림이 계획과 같으면(시각, 제목, 내용) 다시 만들지 않는다.
    private static func matches(_ request: UNNotificationRequest, _ reminder: PlannedReminder) -> Bool {
        request.content.title == reminder.title
            && request.content.body == reminder.body
            && (request.content.userInfo[UserInfoKey.fireDate] as? Double) == reminder.fireDate.timeIntervalSince1970
    }

    enum UserInfoKey {
        static let fireDate = "fire"
        static let day = "day"
        static let itemID = "itemID"
        static let taskID = "taskID"
        static let cycleStart = "cycleStart"
    }
}

/// 알림을 눌러 열 날짜. 앱 델리게이트가 넣고, `RootView`가 달력에서 그 날을 연 뒤 비운다.
@MainActor
@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()

    var dayToOpen: LocalDate?
}
