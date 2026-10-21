import Foundation

/// 월간 달력 배치에 쓰는 일정 한 건. 제목과 색은 담지 않고, 화면이 `id`로 찾아서 그린다.
public struct CalendarEntry: Hashable, Sendable, Identifiable {
    public enum Style: Sendable {
        /// 일정(종일, 여러 날, 하루 안의 시간 일정 모두)과 종일·여러 날 할일. 색 막대로 그린다.
        case bar
        /// 하루 안에 끝나는 시간 할일. 색 점과 제목으로 그린다.
        case chip
    }

    public let id: UUID
    public let startDay: LocalDate
    /// 마지막 날(포함). 항상 `startDay` 이후다.
    public let endDay: LocalDate
    public let isAllDay: Bool
    /// 시간 일정의 시작 시각(자정부터 지난 분). 같은 날 막대와 칩을 시간순으로 놓는 데 쓴다.
    public let startMinute: Int?
    /// 할일(체크박스)인지. 달력에서 하루 안의 시간 할일만 칩으로 그린다.
    public let isTask: Bool

    public init(id: UUID, startDay: LocalDate, endDay: LocalDate, isAllDay: Bool, startMinute: Int? = nil, isTask: Bool = false) {
        self.id = id
        self.startDay = startDay
        self.endDay = max(startDay, endDay)
        self.isAllDay = isAllDay
        self.startMinute = startMinute
        self.isTask = isTask
    }

    /// 하루 안에 끝나는 시간 일정·할일(하루 상세의 "시간" 묶음).
    public var isTimedWithinOneDay: Bool {
        !isAllDay && endDay == startDay
    }

    /// 달력에 그리는 모양(사용자 결정 2026-10-21: 일정은 하루짜리 시간 일정도 막대로 그린다).
    public var style: Style {
        isTask && isTimedWithinOneDay ? .chip : .bar
    }

    public static func allDay(id: UUID, from startDay: LocalDate, through endDay: LocalDate, isTask: Bool = false) -> CalendarEntry {
        CalendarEntry(id: id, startDay: startDay, endDay: endDay, isAllDay: true, isTask: isTask)
    }

    /// `start..<end` 시간 일정을 `timeZone` 기준 날짜로 바꾼다.
    /// 끝이 자정 정각이면 그 전날까지로 본다(22:00–24:00은 하루짜리). 끝이 시작보다 앞서면 시작일 하루로 본다.
    public static func timed(id: UUID, start: Date, end: Date, timeZone: TimeZone = .current, isTask: Bool = false) -> CalendarEntry {
        let startDay = LocalDate(start, in: timeZone)
        let endDay = end > start ? LocalDate(end.addingTimeInterval(-1), in: timeZone) : startDay
        let startMinute = LocalDate.minuteOfDay(start, in: timeZone)
        return CalendarEntry(id: id, startDay: startDay, endDay: endDay, isAllDay: false, startMinute: startMinute, isTask: isTask)
    }
}
