import DayGridCore
import Foundation

/// 목록에 보이는 일정 시간 표기. 예: "종일", "10월 28일 – 11월 3일 · 3/7일", "오전 10:00 – 오전 11:00"
enum ItemTimeText {
    static func describe(_ item: Item, row: DayAgenda.Row, timeZone: TimeZone = .current) -> String {
        if item.isAllDay {
            guard row.totalDays > 1, let startDay = item.startDay, let endDay = item.endDay else { return "종일" }
            return "\(startDay.koreanMonthDayText) – \(endDay.koreanMonthDayText) · \(row.dayNumber)/\(row.totalDays)일"
        }
        guard let start = item.startDate else { return "" }
        let end = item.endDate ?? start
        if row.totalDays <= 1 {
            return "\(time(start, timeZone)) – \(time(end, timeZone))"
        }
        let startDay = LocalDate(start, in: timeZone)
        let endDay = LocalDate(end.addingTimeInterval(-1), in: timeZone)
        return "\(startDay.koreanMonthDayText) \(time(start, timeZone)) – \(endDay.koreanMonthDayText) \(time(end, timeZone))"
    }

    private static func time(_ date: Date, _ timeZone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        return date.formatted(style)
    }
}
