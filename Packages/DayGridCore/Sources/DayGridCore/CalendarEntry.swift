import Foundation

/// 월간 달력 배치에 쓰는 일정 한 건. 제목과 색은 담지 않고, 화면이 `id`로 찾아서 그린다.
public struct CalendarEntry: Hashable, Sendable, Identifiable {
    public enum Style: Sendable {
        /// 종일 일정이나 여러 날에 걸친 일정. 색 막대로 그린다.
        case bar
        /// 하루 안에 끝나는 시간 일정. 색 점과 제목으로 그린다.
        case chip
    }

    public let id: UUID
    public let startDay: LocalDate
    /// 마지막 날(포함). 항상 `startDay` 이후다.
    public let endDay: LocalDate
    public let isAllDay: Bool
    /// 시간 일정의 시작 시각(자정부터 지난 분). 같은 날 칩을 시간순으로 놓는 데 쓴다.
    public let startMinute: Int?

    public init(id: UUID, startDay: LocalDate, endDay: LocalDate, isAllDay: Bool, startMinute: Int? = nil) {
        self.id = id
        self.startDay = startDay
        self.endDay = max(startDay, endDay)
        self.isAllDay = isAllDay
        self.startMinute = startMinute
    }

    public var style: Style {
        isAllDay || endDay > startDay ? .bar : .chip
    }

    public static func allDay(id: UUID, from startDay: LocalDate, through endDay: LocalDate) -> CalendarEntry {
        CalendarEntry(id: id, startDay: startDay, endDay: endDay, isAllDay: true)
    }

    /// `start..<end` 시간 일정을 `timeZone` 기준 날짜로 바꾼다.
    /// 끝이 자정 정각이면 그 전날까지로 본다(22:00–24:00은 하루짜리). 끝이 시작보다 앞서면 시작일 하루로 본다.
    public static func timed(id: UUID, start: Date, end: Date, timeZone: TimeZone = .current) -> CalendarEntry {
        let startDay = LocalDate(start, in: timeZone)
        let endDay = end > start ? LocalDate(end.addingTimeInterval(-1), in: timeZone) : startDay
        let time = LocalDate.gregorian(in: timeZone).dateComponents([.hour, .minute], from: start)
        let startMinute = (time.hour ?? 0) * 60 + (time.minute ?? 0)
        return CalendarEntry(id: id, startDay: startDay, endDay: endDay, isAllDay: false, startMinute: startMinute)
    }
}
