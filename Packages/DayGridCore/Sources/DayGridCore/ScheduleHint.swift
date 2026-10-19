import Foundation

/// 날짜를 뺀 일정의 모양. 종일 여부, 종일 일정의 일수, 시간 일정의 시작 시각과 길이만 담는다.
///
/// 일정을 "나중에"로 미룰 때 남겨 두었다가, 다시 날짜를 정할 때 기본값으로 쓴다.
/// 예: 14:00–15:30 회의를 미뤘다가 목요일로 정하면 목요일 14:00–15:30이 된다.
public struct ScheduleHint: Hashable, Sendable {
    public var isAllDay: Bool
    /// 종일 일정의 일수(1 이상).
    public var dayCount: Int
    /// 시간 일정의 시작 시각(자정부터 지난 분, 0..<1440).
    public var startMinute: Int
    /// 시간 일정의 길이(분, 0 이상).
    public var durationMinutes: Int

    /// 기본값은 종일 하루, 시간 일정이면 09:00부터 한 시간.
    public init(isAllDay: Bool = true, dayCount: Int = 1, startMinute: Int = 9 * 60, durationMinutes: Int = 60) {
        self.isAllDay = isAllDay
        self.dayCount = max(1, dayCount)
        self.startMinute = min(max(0, startMinute), 24 * 60 - 1)
        self.durationMinutes = max(0, durationMinutes)
    }

    /// `start`...`end` 종일 일정의 모양.
    public static func allDay(from start: LocalDate, through end: LocalDate) -> ScheduleHint {
        ScheduleHint(isAllDay: true, dayCount: start.days(until: max(start, end)) + 1)
    }

    /// `start..<end` 시간 일정의 모양. 시작 시각은 `timeZone` 기준이다.
    public static func timed(start: Date, end: Date, timeZone: TimeZone = .current) -> ScheduleHint {
        let minutes = (end.timeIntervalSince(start) / 60).rounded()
        return ScheduleHint(
            isAllDay: false,
            startMinute: LocalDate.minuteOfDay(start, in: timeZone),
            durationMinutes: Int(minutes)
        )
    }

    /// `day`에 시작하는 종일 일정의 마지막 날(포함).
    public func endDay(startingOn day: LocalDate) -> LocalDate {
        day.adding(days: max(1, dayCount) - 1)
    }

    /// `day`에 놓은 시간 일정의 시작 시각.
    public func startDate(on day: LocalDate, in timeZone: TimeZone = .current) -> Date {
        day.date(hour: startMinute / 60, minute: startMinute % 60, in: timeZone)
    }

    /// `day`에 놓은 시간 일정의 끝 시각. 길이가 자정을 넘으면 다음 날이 된다.
    public func endDate(on day: LocalDate, in timeZone: TimeZone = .current) -> Date {
        startDate(on: day, in: timeZone).addingTimeInterval(TimeInterval(durationMinutes * 60))
    }
}

/// 날짜를 빨리 고르는 선택지.
public enum QuickDay: String, CaseIterable, Sendable {
    case today
    case tomorrow
    /// 이번 주 토요일. 오늘이 토요일이나 일요일이면 오늘.
    case weekend

    public func date(from today: LocalDate) -> LocalDate {
        switch self {
        case .today: today
        case .tomorrow: today.adding(days: 1)
        case .weekend: today.weekday == 1 ? today : today.adding(days: 7 - today.weekday)
        }
    }

    public var koreanTitle: String {
        switch self {
        case .today: "오늘"
        case .tomorrow: "내일"
        case .weekend: "이번 주말"
        }
    }
}
