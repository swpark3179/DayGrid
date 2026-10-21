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
    /// "나중에" 목록에서의 순서. 작을수록 위에 있다.
    var inboxOrder: Double = 0
    /// 미루기 전 일정의 모양(`ScheduleHint`). 일수가 0이면 남긴 모양이 없다.
    var hintDayCount: Int = 0
    var hintStartMinute: Int = 0
    var hintDurationMinutes: Int = 0
    /// 고른 알림(`ReminderOption.bit`의 합). 0이면 알림 없음.
    var reminderMask: Int = 0
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

    /// 같은 내용의 새 항목. 완료 표시와 만든 시각은 새로 시작한다.
    func duplicate() -> Item {
        let copy = Item(title: title, isTask: isTask, category: category)
        copy.body = body
        copy.isAllDay = isAllDay
        copy.startDayKey = startDayKey
        copy.endDayKey = endDayKey
        copy.startDate = startDate
        copy.endDate = endDate
        copy.inboxOrder = inboxOrder
        copy.hintDayCount = hintDayCount
        copy.hintStartMinute = hintStartMinute
        copy.hintDurationMinutes = hintDurationMinutes
        copy.reminderMask = reminderMask
        return copy
    }

    /// 할일의 완료 표시를 바꾼다.
    func toggleCompletion(now: Date = Date()) {
        completedAt = completedAt == nil ? now : nil
        updatedAt = now
    }

    var isCompleted: Bool { completedAt != nil }

    /// 날짜를 비워 "나중에 할일"로 돌린다.
    func unschedule() {
        startDayKey = 0
        endDayKey = 0
        startDate = nil
        endDate = nil
        updatedAt = Date()
    }

    /// 날짜를 다시 정할 때 쓸 모양. 미룬 적이 없으면 기본값(종일 하루, 시간 일정이면 09:00부터 한 시간).
    var scheduleHint: ScheduleHint {
        guard hintDayCount > 0 else { return ScheduleHint(isAllDay: isAllDay) }
        return ScheduleHint(
            isAllDay: isAllDay,
            dayCount: hintDayCount,
            startMinute: hintStartMinute,
            durationMinutes: hintDurationMinutes
        )
    }

    /// 지금 일정의 모양. 날짜가 없으면 `nil`.
    func currentScheduleHint(in timeZone: TimeZone = .current) -> ScheduleHint? {
        if isAllDay {
            guard let start = startDay else { return nil }
            return .allDay(from: start, through: endDay ?? start)
        }
        guard isScheduled, let startDate else { return nil }
        return .timed(start: startDate, end: endDate ?? startDate, timeZone: timeZone)
    }

    /// 날짜를 비우고 "나중에" 목록의 `order` 자리에 넣는다.
    /// 지금 일정의 모양은 다음에 날짜를 정할 때 기본값으로 쓰도록 남긴다.
    func moveToInbox(order: Double, timeZone: TimeZone = .current) {
        if let hint = currentScheduleHint(in: timeZone) {
            hintDayCount = hint.dayCount
            hintStartMinute = hint.startMinute
            hintDurationMinutes = hint.durationMinutes
        }
        unschedule()
        inboxOrder = order
    }

    /// `day`에 `hint` 모양으로 일정을 정한다.
    func schedule(on day: LocalDate, using hint: ScheduleHint, timeZone: TimeZone = .current) {
        if hint.isAllDay {
            scheduleAllDay(from: day, through: hint.endDay(startingOn: day))
        } else {
            scheduleTimed(
                start: hint.startDate(on: day, in: timeZone),
                end: hint.endDate(on: day, in: timeZone),
                timeZone: timeZone
            )
        }
    }

    /// 달력 배치용 값. 날짜가 없으면 `nil`.
    func calendarEntry(in timeZone: TimeZone = .current) -> CalendarEntry? {
        if isAllDay {
            guard let start = startDay else { return nil }
            return .allDay(id: id, from: start, through: endDay ?? start, isTask: isTask)
        }
        guard isScheduled, let startDate else { return nil }
        return .timed(id: id, start: startDate, end: endDate ?? startDate, timeZone: timeZone, isTask: isTask)
    }

    /// 일정을 `days`일 앞(음수면 뒤)으로 옮긴다. 모양(종일 일수, 시작 시각과 길이)과 완료 표시는 그대로다.
    /// 하루 상세에서 꾹 눌러 다른 날로 끌어 놓을 때 쓴다. 날짜가 없거나 0일이면 아무것도 하지 않는다.
    func move(byDays days: Int, timeZone: TimeZone = .current) {
        guard days != 0, let entry = calendarEntry(in: timeZone), let hint = currentScheduleHint(in: timeZone) else { return }
        schedule(on: entry.startDay.adding(days: days), using: hint, timeZone: timeZone)
    }

    /// `range`와 겹치는 일정. 시간대 차이를 흡수하려고 앞뒤로 하루씩 넓혀서 찾는다.
    static func predicate(overlapping range: ClosedRange<LocalDate>) -> Predicate<Item> {
        let lower = range.lowerBound.adding(days: -1).yyyymmdd
        let upper = range.upperBound.adding(days: 1).yyyymmdd
        return #Predicate<Item> { item in
            item.startDayKey > 0 && item.startDayKey <= upper && item.endDayKey >= lower
        }
    }

    /// 날짜가 없는 항목("나중에" 목록).
    static var inboxPredicate: Predicate<Item> {
        #Predicate<Item> { item in
            item.startDayKey == 0
        }
    }

    /// "나중에" 목록 맨 위에 넣을 때 쓸 순서 값.
    static func topInboxOrder(in context: ModelContext) -> Double {
        var descriptor = FetchDescriptor<Item>(predicate: inboxPredicate, sortBy: [SortDescriptor(\.inboxOrder)])
        descriptor.fetchLimit = 1
        let first = (try? context.fetch(descriptor))?.first?.inboxOrder ?? 0
        return first - 1
    }
}
