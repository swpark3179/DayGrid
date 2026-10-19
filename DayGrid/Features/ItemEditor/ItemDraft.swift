import DayGridCore
import Foundation

/// 편집 화면이 다루는 값. 저장하기 전까지는 모델을 건드리지 않는다.
///
/// 종일 일정이면 `start`/`end`의 날짜만 쓰고, 시간 일정이면 시각까지 쓴다.
/// 이렇게 두면 종일 토글을 켰다 꺼도 고른 날짜가 유지된다.
/// 날짜를 끄면(`hasDate == false`) 저장할 때 "나중에" 목록으로 들어가고, 고른 모양은 힌트로 남는다.
struct ItemDraft: Equatable {
    var title = ""
    var isTask = false
    var hasDate = true
    var isAllDay = false
    var start: Date
    var end: Date
    var categoryID: UUID?
    var note = ""
    /// 고른 알림(`ReminderOption.bit`의 합)
    var reminderMask = 0

    private init(start: Date, end: Date, categoryID: UUID?) {
        self.start = start
        self.end = end
        self.categoryID = categoryID
    }

    /// `day`에 새 일정을 만들 때의 기본값. 오늘이면 다음 정시부터, 다른 날이면 09:00부터 한 시간.
    static func new(on day: LocalDate, categoryID: UUID?, now: Date = Date(), timeZone: TimeZone = .current) -> ItemDraft {
        var hour = 9
        if day == LocalDate(now, in: timeZone) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            hour = min(calendar.component(.hour, from: now) + 1, 23)
        }
        let start = day.date(hour: hour, in: timeZone)
        return ItemDraft(start: start, end: start.addingTimeInterval(3600), categoryID: categoryID)
    }

    /// 이미 있는 일정을 고칠 때. 날짜가 없는 항목이면 미룰 때 남긴 모양을 `today`에 놓아 둔다.
    init(item: Item, today: LocalDate? = nil, timeZone: TimeZone = .current) {
        if item.isAllDay, let startDay = item.startDay {
            start = startDay.date(hour: 9, in: timeZone)
            end = (item.endDay ?? startDay).date(hour: 10, in: timeZone)
        } else if item.isScheduled, let startDate = item.startDate {
            start = startDate
            end = item.endDate ?? startDate.addingTimeInterval(3600)
        } else {
            let hint = item.scheduleHint
            let day = today ?? LocalDate.today(in: timeZone)
            if hint.isAllDay {
                start = day.date(hour: 9, in: timeZone)
                end = hint.endDay(startingOn: day).date(hour: 10, in: timeZone)
            } else {
                start = hint.startDate(on: day, in: timeZone)
                end = hint.endDate(on: day, in: timeZone)
            }
        }
        title = item.title
        isTask = item.isTask
        hasDate = item.isScheduled
        isAllDay = item.isAllDay
        categoryID = item.category?.id
        note = item.body ?? ""
        reminderMask = item.reminderMask
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSave: Bool {
        !trimmedTitle.isEmpty
    }

    /// 시작을 옮기면 기간을 유지한 채 끝도 같이 옮긴다.
    mutating func moveStart(to newStart: Date) {
        let duration = max(0, end.timeIntervalSince(start))
        start = newStart
        end = newStart.addingTimeInterval(duration)
    }

    /// 종료를 고를 수 있는 가장 이른 값. 종일 일정이면 시작한 날 0시.
    func earliestEnd(timeZone: TimeZone = .current) -> Date {
        isAllDay ? LocalDate(start, in: timeZone).date(in: timeZone) : start
    }

    /// 초안을 모델에 반영한다. 할일이 아니게 되면 완료 표시도 지운다.
    ///
    /// 날짜를 끈 채 저장하면 고른 모양을 힌트로 남기고 날짜를 비운다.
    /// 날짜가 있던 항목은 "나중에" 목록의 `inboxOrder` 자리로 가고, 원래 목록에 있던 항목은 순서를 그대로 둔다.
    func apply(to item: Item, categories: [ItemCategory], inboxOrder: Double = 0, timeZone: TimeZone = .current) {
        let wasInInbox = !item.isScheduled
        item.title = trimmedTitle
        item.isTask = isTask
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        item.body = trimmedNote.isEmpty ? nil : note
        item.category = categories.first { $0.id == categoryID }
        item.reminderMask = reminderMask
        if isAllDay {
            item.scheduleAllDay(from: LocalDate(start, in: timeZone), through: LocalDate(end, in: timeZone))
        } else {
            item.scheduleTimed(start: start, end: end, timeZone: timeZone)
        }
        if !hasDate {
            item.moveToInbox(order: wasInInbox ? item.inboxOrder : inboxOrder, timeZone: timeZone)
        }
        if !isTask {
            item.completedAt = nil
        }
        item.updatedAt = Date()
    }
}
