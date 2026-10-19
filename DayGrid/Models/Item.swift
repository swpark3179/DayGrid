import DayGridCore
import Foundation
import SwiftData

/// 일정과 할일을 함께 담는 모델. 날짜가 없으면 "나중에 할일"이다.
///
/// - 종일/기간 일정: `isAllDay == true`, 날짜는 `startDayKey`...`endDayKey`(yyyymmdd, 포함)
/// - 시간 일정: `isAllDay == false`, 실제 시각은 `startDate`/`endDate`.
///   이때 `startDayKey`/`endDayKey`는 저장할 때의 시간대 기준으로 채운 **조회용 색인**일 뿐이고,
///   표시할 날짜는 `calendarEntry(in:)`가 실제 시각으로 다시 계산한다.
@Model
final class Item {
    var id: UUID = UUID()
    var title: String = ""
    /// 마크다운 본문(Phase 5).
    var body: String?
    /// 체크박스로 완료할 수 있는 할일인지.
    var isTask: Bool = false
    var isAllDay: Bool = true
    /// yyyymmdd. 0이면 날짜 없음.
    var startDayKey: Int = 0
    /// yyyymmdd(포함). 0이면 날짜 없음.
    var endDayKey: Int = 0
    var startDate: Date?
    var endDate: Date?
    var completedAt: Date?
    /// "나중에" 목록에서의 순서(Phase 4).
    var inboxOrder: Double = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var category: ItemCategory?

    init(title: String, isTask: Bool = false, category: ItemCategory? = nil) {
        self.title = title
        self.isTask = isTask
        self.category = category
    }
}

extension Item {
    var isScheduled: Bool { startDayKey != 0 }

    var startDay: LocalDate? { LocalDate(yyyymmdd: startDayKey) }

    var endDay: LocalDate? { LocalDate(yyyymmdd: endDayKey) }

    /// 종일(하루 또는 여러 날) 일정으로 정한다.
    func scheduleAllDay(from start: LocalDate, through end: LocalDate) {
        isAllDay = true
        startDayKey = start.yyyymmdd
        endDayKey = max(start, end).yyyymmdd
        startDate = nil
        endDate = nil
        updatedAt = Date()
    }

    /// 시간 일정으로 정한다. 끝이 시작보다 앞서면 시작 시각으로 맞춘다.
    func scheduleTimed(start: Date, end: Date, timeZone: TimeZone = .current) {
        let clampedEnd = max(start, end)
        isAllDay = false
        startDate = start
        endDate = clampedEnd
        let entry = CalendarEntry.timed(id: id, start: start, end: clampedEnd, timeZone: timeZone)
        startDayKey = entry.startDay.yyyymmdd
        endDayKey = entry.endDay.yyyymmdd
        updatedAt = Date()
    }

    /// 날짜를 비워 "나중에 할일"로 돌린다.
    func unschedule() {
        startDayKey = 0
        endDayKey = 0
        startDate = nil
        endDate = nil
        updatedAt = Date()
    }

    /// 달력 배치용 값. 날짜가 없으면 `nil`.
    func calendarEntry(in timeZone: TimeZone = .current) -> CalendarEntry? {
        if isAllDay {
            guard let start = startDay else { return nil }
            return .allDay(id: id, from: start, through: endDay ?? start)
        }
        guard isScheduled, let startDate else { return nil }
        return .timed(id: id, start: startDate, end: endDate ?? startDate, timeZone: timeZone)
    }

    /// `range`와 겹치는 일정. 시간대 차이를 흡수하려고 앞뒤로 하루씩 넓혀서 찾는다.
    static func predicate(overlapping range: ClosedRange<LocalDate>) -> Predicate<Item> {
        let lower = range.lowerBound.adding(days: -1).yyyymmdd
        let upper = range.upperBound.adding(days: 1).yyyymmdd
        return #Predicate<Item> { item in
            item.startDayKey > 0 && item.startDayKey <= upper && item.endDayKey >= lower
        }
    }
}
