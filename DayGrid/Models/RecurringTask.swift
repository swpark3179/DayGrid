import DayGridCore
import Foundation
import SwiftData

/// 매일·매주·매월 반복하는 할일. 주기마다 한 번 완료하며, 완료 기록은 `RecurrenceCompletion`에 남긴다.
@Model
final class RecurringTask {
    var id: UUID = UUID()
    var title: String = ""
    /// 0 = 매일, 1 = 매주, 2 = 매월
    var ruleKind: Int = 0
    /// 매주: 고른 요일의 비트(1 = 일요일 … 7 = 토요일, `1 << weekday`)
    var weekdayMask: Int = 0
    /// 매월: 날짜(1–31). 0이면 말일.
    var monthDay: Int = 1
    /// yyyymmdd
    var startDayKey: Int = 0
    /// yyyymmdd(포함). 0이면 끝나지 않는다.
    var endDayKey: Int = 0
    /// 주기가 시작되는 날 알릴 시각(자정부터 지난 분). 음수면 알리지 않는다.
    var notifyMinute: Int = 9 * 60
    var isActive: Bool = true
    var sortOrder: Double = 0
    var createdAt: Date = Date()
    var category: ItemCategory?

    @Relationship(deleteRule: .cascade, inverse: \RecurrenceCompletion.task)
    var completions: [RecurrenceCompletion]? = []

    init(title: String, rule: RecurrenceRule, startDay: LocalDate) {
        self.title = title
        self.startDayKey = startDay.yyyymmdd
        self.rule = rule
    }
}

/// 반복 할일의 주기 하나를 완료한 기록.
@Model
final class RecurrenceCompletion {
    var id: UUID = UUID()
    /// 완료한 주기의 시작일(yyyymmdd)
    var cycleStartKey: Int = 0
    /// 체크한 날(yyyymmdd). 달력에서 이 날에 ✓를 찍는다.
    var completedDayKey: Int = 0
    var completedAt: Date = Date()
    var task: RecurringTask?

    init(cycleStart: LocalDate, completedOn: LocalDate) {
        self.cycleStartKey = cycleStart.yyyymmdd
        self.completedDayKey = completedOn.yyyymmdd
    }
}

extension RecurringTask {
    var rule: RecurrenceRule {
        get {
            switch ruleKind {
            case 1:
                return .weekly(weekdays: Set((1...7).filter { weekdayMask & (1 << $0) != 0 }))
            case 2:
                return monthDay == 0 ? .monthlyLastDay : .monthly(day: monthDay)
            default:
                return .daily
            }
        }
        set {
            switch newValue {
            case .daily:
                ruleKind = 0
            case .weekly(let weekdays):
                ruleKind = 1
                weekdayMask = weekdays.reduce(0) { $0 | (1 << $1) }
            case .monthly(let day):
                ruleKind = 2
                monthDay = min(max(1, day), 31)
            case .monthlyLastDay:
                ruleKind = 2
                monthDay = 0
            }
        }
    }

    var startDay: LocalDate? { LocalDate(yyyymmdd: startDayKey) }

    var endDay: LocalDate? { LocalDate(yyyymmdd: endDayKey) }

    var recurrence: Recurrence? {
        guard let startDay else { return nil }
        return Recurrence(rule: rule, startDay: startDay, endDay: endDay)
    }

    /// 주기 시작일 → 체크한 날
    var completionDays: [LocalDate: LocalDate] {
        var result: [LocalDate: LocalDate] = [:]
        for completion in completions ?? [] {
            if let start = LocalDate(yyyymmdd: completion.cycleStartKey), let done = LocalDate(yyyymmdd: completion.completedDayKey) {
                result[start] = done
            }
        }
        return result
    }

    /// `date`가 속한 주기와 그 상태. 주기가 없으면 `nil`.
    func cycleStatus(on date: LocalDate, today: LocalDate) -> (cycle: RecurrenceCycle, status: RecurrenceStatus)? {
        guard let cycle = recurrence?.cycle(containing: date) else { return nil }
        return (cycle, Recurrence.status(of: cycle, today: today, completedOn: completionDays[cycle.start]))
    }

    /// 지금 주기의 체크를 바꾼다. 같은 주기에 완료 기록이 둘 생기지 않는다.
    func toggleCompletion(of cycle: RecurrenceCycle, today: LocalDate, in context: ModelContext) {
        let starts = Set(completionDays.keys)
        switch RecurrenceToggle.action(for: cycle, completedCycleStarts: starts, today: today) {
        case .complete(let cycleStart, let completedOn):
            let completion = RecurrenceCompletion(cycleStart: cycleStart, completedOn: completedOn)
            context.insert(completion)
            completion.task = self
        case .uncomplete(let cycleStart):
            for completion in completions ?? [] where completion.cycleStartKey == cycleStart.yyyymmdd {
                context.delete(completion)
            }
        }
        try? context.save()
    }
}
