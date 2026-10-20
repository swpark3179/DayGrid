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

    static func time(_ date: Date, _ timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// 하루 상세 타임라인 왼쪽의 정시 표기. 예: "오전 9시", "오후 1시". `minute`이 1440이면 다음 날 자정이다.
    static func hourLabel(_ minute: Int, on day: LocalDate, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated))
        style.timeZone = timeZone
        let date = day.adding(days: minute / (24 * 60)).date(hour: minute % (24 * 60) / 60, in: timeZone)
        return date.formatted(style)
    }
}
