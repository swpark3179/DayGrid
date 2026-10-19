/// 반복 규칙. 요일은 `LocalDate.weekday`와 같이 1 = 일요일 … 7 = 토요일.
public enum RecurrenceRule: Hashable, Sendable {
    case daily
    /// 고른 요일마다. 요일을 하나도 고르지 않으면 발생일이 없다.
    case weekly(weekdays: Set<Int>)
    /// 매월 `day`일. 그 달에 없는 날(31일 등)은 말일로 맞춘다.
    case monthly(day: Int)
    /// 매월 말일
    case monthlyLastDay

    /// "매일", "매주 월·수·금", "매월 15일", "매월 말일"
    public var koreanText: String {
        switch self {
        case .daily:
            return "매일"
        case .weekly(let weekdays):
            // 월요일부터 읽는다.
            let ordered = [2, 3, 4, 5, 6, 7, 1].filter { weekdays.contains($0) }
            if ordered.count == 7 { return "매주 모든 요일" }
            if ordered.isEmpty { return "매주(요일 없음)" }
            return "매주 " + ordered.map { LocalDate.koreanWeekdaySymbols[$0 - 1] }.joined(separator: "·")
        case .monthly(let day):
            return "매월 \(day)일"
        case .monthlyLastDay:
            return "매월 말일"
        }
    }
}

/// 반복 할일의 주기 하나: `[start, 다음 발생일)`. `end`는 다음 발생일 전날(포함)이다.
public struct RecurrenceCycle: Hashable, Sendable {
    public let start: LocalDate
    public let end: LocalDate

    public init(start: LocalDate, end: LocalDate) {
        self.start = start
        self.end = max(start, end)
    }

    public func contains(_ date: LocalDate) -> Bool {
        start <= date && date <= end
    }
}

/// 주기의 상태. 놓침은 저장하지 않고 이렇게 계산으로 구한다.
public enum RecurrenceStatus: Hashable, Sendable {
    /// `completedOn`에 완료했다.
    case done(completedOn: LocalDate)
    /// 아직 주기 안이고 완료하지 않았다. `dayNumber`는 주기의 몇째 날인지(1부터).
    case pending(dayNumber: Int)
    /// 주기가 지났는데 완료하지 않았다.
    case missed
    /// 아직 시작하지 않은 주기
    case upcoming
}

/// 반복 할일 계산: 발생일, 날짜가 속한 주기, 주기 상태, 월 요약.
///
/// - 주기는 발생일부터 다음 발생일 전날까지다. 매일은 하루가 주기 하나다.
/// - `startDay` 이전과 `endDay` 이후에는 발생일이 없다. 마지막 주기도 원래 길이만큼 이어진다.
public struct Recurrence: Hashable, Sendable {
    public var rule: RecurrenceRule
    public var startDay: LocalDate
    public var endDay: LocalDate?

    public init(rule: RecurrenceRule, startDay: LocalDate, endDay: LocalDate? = nil) {
        self.rule = rule
        self.startDay = startDay
        self.endDay = endDay
    }

    /// `range` 안의 발생일(빠른 순).
    public func occurrences(in range: ClosedRange<LocalDate>) -> [LocalDate] {
        let lower = max(range.lowerBound, startDay)
        let upper = endDay.map { min(range.upperBound, $0) } ?? range.upperBound
        guard lower <= upper else { return [] }
        return ruleOccurrences(from: lower, through: upper)
    }

    /// `date`가 속한 주기. 첫 발생일 전이나 마지막 주기 뒤면 `nil`.
    public func cycle(containing date: LocalDate) -> RecurrenceCycle? {
        guard date >= startDay, let start = latestOccurrence(onOrBefore: date), start >= startDay else { return nil }
        if let endDay, start > endDay { return nil }
        guard let next = nextRuleOccurrence(after: start) else { return nil }
        let cycle = RecurrenceCycle(start: start, end: next.adding(days: -1))
        return cycle.contains(date) ? cycle : nil
    }

    /// `range`에서 시작하는 주기들.
    public func cycles(startingIn range: ClosedRange<LocalDate>) -> [RecurrenceCycle] {
        occurrences(in: range).compactMap { start in
            nextRuleOccurrence(after: start).map { RecurrenceCycle(start: start, end: $0.adding(days: -1)) }
        }
    }

    /// `cycle`의 상태. `completedOn`은 그 주기의 완료 기록(체크한 날), 없으면 `nil`.
    public static func status(of cycle: RecurrenceCycle, today: LocalDate, completedOn: LocalDate?) -> RecurrenceStatus {
        if let completedOn { return .done(completedOn: completedOn) }
        if today < cycle.start { return .upcoming }
        if today <= cycle.end { return .pending(dayNumber: cycle.start.days(until: today) + 1) }
        return .missed
    }

    /// `month`(그 달의 아무 날)에 시작한 주기 중 오늘까지 시작한 것과 그중 완료한 것. "이번 달 3/4 완료"
    public func monthSummary(month: LocalDate, today: LocalDate, completedCycleStarts: Set<LocalDate>) -> (done: Int, total: Int) {
        let upper = min(month.lastDayOfMonth, today)
        guard month.firstDayOfMonth <= upper else { return (0, 0) }
        let starts = occurrences(in: month.firstDayOfMonth...upper)
        return (starts.filter { completedCycleStarts.contains($0) }.count, starts.count)
    }

    // MARK: - 규칙별 발생일(시작일·종료일과 무관하게)

    private func ruleOccurrences(from lower: LocalDate, through upper: LocalDate) -> [LocalDate] {
        switch rule {
        case .daily:
            return Array(lower...upper)
        case .weekly(let weekdays):
            return (lower...upper).filter { weekdays.contains($0.weekday) }
        case .monthly, .monthlyLastDay:
            var result: [LocalDate] = []
            var month = lower.firstDayOfMonth
            while month <= upper {
                let date = monthlyDate(in: month)
                if lower <= date && date <= upper {
                    result.append(date)
                }
                month = month.adding(months: 1)
            }
            return result
        }
    }

    private func monthlyDate(in month: LocalDate) -> LocalDate {
        switch rule {
        case .monthly(let day):
            let clamped = min(max(1, day), month.numberOfDaysInMonth)
            return month.adding(days: clamped - 1)
        default:
            return month.lastDayOfMonth
        }
    }

    /// 규칙상 `date` 또는 그 전의 마지막 발생일.
    private func latestOccurrence(onOrBefore date: LocalDate) -> LocalDate? {
        switch rule {
        case .daily:
            return date
        case .weekly(let weekdays):
            return (0..<7).lazy.map { date.adding(days: -$0) }.first { weekdays.contains($0.weekday) }
        case .monthly, .monthlyLastDay:
            let thisMonth = monthlyDate(in: date.firstDayOfMonth)
            return thisMonth <= date ? thisMonth : monthlyDate(in: date.firstDayOfMonth.adding(months: -1))
        }
    }

    /// 규칙상 `date` 다음의 첫 발생일(종료일과 무관).
    private func nextRuleOccurrence(after date: LocalDate) -> LocalDate? {
        switch rule {
        case .daily:
            return date.adding(days: 1)
        case .weekly(let weekdays):
            return (1...7).lazy.map { date.adding(days: $0) }.first { weekdays.contains($0.weekday) }
        case .monthly, .monthlyLastDay:
            let thisMonth = monthlyDate(in: date.firstDayOfMonth)
            return thisMonth > date ? thisMonth : monthlyDate(in: date.firstDayOfMonth.adding(months: 1))
        }
    }
}

/// 체크박스를 눌렀을 때 할 일. 같은 주기에 완료 기록이 이미 있으면 지우고(체크 취소), 없으면 하나만 더한다.
public enum RecurrenceToggle: Hashable, Sendable {
    case complete(cycleStart: LocalDate, completedOn: LocalDate)
    case uncomplete(cycleStart: LocalDate)

    public static func action(for cycle: RecurrenceCycle, completedCycleStarts: Set<LocalDate>, today: LocalDate) -> RecurrenceToggle {
        completedCycleStarts.contains(cycle.start)
            ? .uncomplete(cycleStart: cycle.start)
            : .complete(cycleStart: cycle.start, completedOn: today)
    }
}
