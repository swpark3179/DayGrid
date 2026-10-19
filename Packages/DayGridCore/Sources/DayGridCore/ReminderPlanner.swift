import Foundation

/// 일정·할일에 고를 수 있는 알림. 시간 일정과 종일 일정의 선택지가 다르다.
public enum ReminderOption: Int, CaseIterable, Sendable {
    /// 시간 일정: 시작 시각
    case atStart = 0
    /// 시간 일정: 10분 전
    case tenMinutesBefore = 1
    /// 시간 일정: 1시간 전
    case oneHourBefore = 2
    /// 시간 일정: 하루 전
    case oneDayBefore = 3
    /// 종일 일정: 그날 09:00
    case sameDayMorning = 4
    /// 종일 일정: 전날 09:00
    case previousDayMorning = 5

    public static let timedOptions: [ReminderOption] = [.atStart, .tenMinutesBefore, .oneHourBefore, .oneDayBefore]
    public static let allDayOptions: [ReminderOption] = [.sameDayMorning, .previousDayMorning]
    /// 종일 일정 알림 시각(09:00)
    public static let allDayMinute = 9 * 60

    public var bit: Int { 1 << rawValue }

    /// 비트 묶음에서 고른 알림들.
    public static func options(in mask: Int) -> [ReminderOption] {
        allCases.filter { mask & $0.bit != 0 }
    }

    public static func mask(of options: some Sequence<ReminderOption>) -> Int {
        options.reduce(0) { $0 | $1.bit }
    }

    public var koreanText: String {
        switch self {
        case .atStart: "정시"
        case .tenMinutesBefore: "10분 전"
        case .oneHourBefore: "1시간 전"
        case .oneDayBefore: "하루 전"
        case .sameDayMorning: "당일 오전 9시"
        case .previousDayMorning: "전날 오전 9시"
        }
    }
}

/// 알림 하나의 계획. 식별자는 같은 알림이면 늘 같아서, 대기 중인 알림과 비교해 바뀐 것만 고칠 수 있다.
public struct PlannedReminder: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// 일정·할일. `isTask`면 "완료" 동작을 붙인다.
        case item(id: UUID, isTask: Bool)
        case birthday(personID: UUID)
        /// 반복 할일의 한 주기. "완료" 동작을 붙인다.
        case recurring(taskID: UUID, cycleStart: LocalDate)
    }

    public let identifier: String
    public let fireDate: Date
    public let title: String
    public let body: String
    public let kind: Kind
    /// 알림을 누르면 열 날짜
    public let day: LocalDate
}

/// 앞으로 `horizonDays`일 안에 울릴 알림을 계산한다. iOS는 앱당 대기 알림을 64개까지만 두므로 가까운 순으로 `limit`개(기본 60)만 고른다.
public enum ReminderPlanner {
    public static let defaultLimit = 60
    public static let defaultHorizonDays = 30
    public static let identifierPrefix = "daygrid."

    public struct ItemInput: Sendable {
        public let id: UUID
        public let title: String
        public let isTask: Bool
        public let isCompleted: Bool
        public let isAllDay: Bool
        public let startDay: LocalDate?
        public let startDate: Date?
        public let options: [ReminderOption]

        public init(id: UUID, title: String, isTask: Bool, isCompleted: Bool, isAllDay: Bool, startDay: LocalDate?, startDate: Date?, options: [ReminderOption]) {
            self.id = id
            self.title = title
            self.isTask = isTask
            self.isCompleted = isCompleted
            self.isAllDay = isAllDay
            self.startDay = startDay
            self.startDate = startDate
            self.options = options
        }
    }

    public struct BirthdayInput: Sendable {
        public let id: UUID
        public let name: String
        public let birthday: Birthday

        public init(id: UUID, name: String, birthday: Birthday) {
            self.id = id
            self.name = name
            self.birthday = birthday
        }
    }

    /// 생일 알림 설정. `daysBefore`가 비어 있으면 생일 알림을 보내지 않는다.
    public struct BirthdaySettings: Sendable {
        public let daysBefore: [Int]
        public let minute: Int

        public init(daysBefore: [Int], minute: Int = 9 * 60) {
            self.daysBefore = daysBefore
            self.minute = minute
        }

        public static let off = BirthdaySettings(daysBefore: [])
    }

    public struct RecurringInput: Sendable {
        public let id: UUID
        public let title: String
        public let recurrence: Recurrence
        /// 주기가 시작되는 날 알릴 시각(자정부터 지난 분). 음수면 알리지 않는다.
        public let notifyMinute: Int
        public let completedCycleStarts: Set<LocalDate>

        public init(id: UUID, title: String, recurrence: Recurrence, notifyMinute: Int, completedCycleStarts: Set<LocalDate>) {
            self.id = id
            self.title = title
            self.recurrence = recurrence
            self.notifyMinute = notifyMinute
            self.completedCycleStarts = completedCycleStarts
        }
    }

    public static func plan(
        items: [ItemInput],
        birthdays: [BirthdayInput],
        birthdaySettings: BirthdaySettings,
        recurring: [RecurringInput],
        now: Date,
        timeZone: TimeZone = .current,
        horizonDays: Int = defaultHorizonDays,
        limit: Int = defaultLimit
    ) -> [PlannedReminder] {
        let today = LocalDate(now, in: timeZone)
        let horizonEnd = today.adding(days: horizonDays)
        let horizon = horizonEnd.date(in: timeZone)
        guard horizon > now else { return [] }

        var reminders: [PlannedReminder] = []
        reminders += items.flatMap { itemReminders($0, timeZone: timeZone) }
        reminders += birthdays.flatMap { birthdayReminders($0, settings: birthdaySettings, today: today, horizonEnd: horizonEnd, timeZone: timeZone) }
        reminders += recurring.flatMap { recurringReminders($0, today: today, horizonEnd: horizonEnd, timeZone: timeZone) }

        return reminders
            .filter { $0.fireDate > now && $0.fireDate < horizon }
            .sorted { ($0.fireDate, $0.identifier) < ($1.fireDate, $1.identifier) }
            .prefix(max(0, limit))
            .map(\.self)
    }

    // MARK: - 종류별

    private static func itemReminders(_ item: ItemInput, timeZone: TimeZone) -> [PlannedReminder] {
        guard !(item.isTask && item.isCompleted), let startDay = item.startDay else { return [] }
        return item.options.compactMap { option -> PlannedReminder? in
            let fireDate: Date
            let body: String
            if item.isAllDay {
                switch option {
                case .sameDayMorning:
                    fireDate = startDay.date(hour: ReminderOption.allDayMinute / 60, in: timeZone)
                    body = "오늘 \(startDay.koreanMonthDayWeekdayText)"
                case .previousDayMorning:
                    fireDate = startDay.adding(days: -1).date(hour: ReminderOption.allDayMinute / 60, in: timeZone)
                    body = "내일 \(startDay.koreanMonthDayWeekdayText)"
                default:
                    return nil
                }
            } else {
                guard let start = item.startDate else { return nil }
                let minutes: Int
                switch option {
                case .atStart: minutes = 0
                case .tenMinutesBefore: minutes = 10
                case .oneHourBefore: minutes = 60
                case .oneDayBefore: minutes = 24 * 60
                default: return nil
                }
                fireDate = start.addingTimeInterval(TimeInterval(-minutes * 60))
                body = minutes == 0 ? "지금 시작" : "\(option.koreanText) · \(timeText(start, timeZone: timeZone)) 시작"
            }
            return PlannedReminder(
                identifier: "\(identifierPrefix)item.\(item.id.uuidString).\(option.rawValue)",
                fireDate: fireDate,
                title: item.title,
                body: body,
                kind: .item(id: item.id, isTask: item.isTask),
                day: startDay
            )
        }
    }

    private static func birthdayReminders(
        _ person: BirthdayInput,
        settings: BirthdaySettings,
        today: LocalDate,
        horizonEnd: LocalDate,
        timeZone: TimeZone
    ) -> [PlannedReminder] {
        guard !settings.daysBefore.isEmpty else { return [] }
        let latestLead = settings.daysBefore.max() ?? 0
        let birthdays = person.birthday.occurrences(in: today...horizonEnd.adding(days: latestLead))
        return birthdays.flatMap { date in
            settings.daysBefore.map { daysBefore in
                let fireDay = date.adding(days: -daysBefore)
                return PlannedReminder(
                    identifier: "\(identifierPrefix)birthday.\(person.id.uuidString).\(date.yyyymmdd).\(daysBefore)",
                    fireDate: fireDay.date(hour: settings.minute / 60, minute: settings.minute % 60, in: timeZone),
                    title: "🎂 \(person.name) 생일",
                    body: daysBefore == 0 ? "오늘입니다" : "\(daysBefore)일 남았습니다 · \(date.koreanMonthDayWeekdayText)",
                    kind: .birthday(personID: person.id),
                    day: date
                )
            }
        }
    }

    /// 주기가 시작되는 날 한 번만 알린다. 이미 완료한 주기는 알리지 않는다.
    private static func recurringReminders(
        _ task: RecurringInput,
        today: LocalDate,
        horizonEnd: LocalDate,
        timeZone: TimeZone
    ) -> [PlannedReminder] {
        guard task.notifyMinute >= 0 else { return [] }
        return task.recurrence.occurrences(in: today...horizonEnd)
            .filter { !task.completedCycleStarts.contains($0) }
            .map { start in
                PlannedReminder(
                    identifier: "\(identifierPrefix)recurring.\(task.id.uuidString).\(start.yyyymmdd)",
                    fireDate: start.date(hour: task.notifyMinute / 60, minute: task.notifyMinute % 60, in: timeZone),
                    title: task.title,
                    body: "\(task.recurrence.rule.koreanText) 반복 할일",
                    kind: .recurring(taskID: task.id, cycleStart: start),
                    day: start
                )
            }
    }

    private static func timeText(_ date: Date, timeZone: TimeZone) -> String {
        let minute = LocalDate.minuteOfDay(date, in: timeZone)
        let hour = minute / 60
        let period = hour < 12 ? "오전" : "오후"
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        return minute % 60 == 0 ? "\(period) \(displayHour)시" : "\(period) \(displayHour)시 \(minute % 60)분"
    }
}
