import Foundation
import SwiftData

/// 되돌리기(`UndoToastState`)를 위해 남겨 두는 `Item`의 값 전부.
///
/// - 지운 일정은 `makeItem()`으로 같은 `id`와 만든 시각, 완료 표시까지 그대로 되살린다.
/// - 날짜를 바꾼 일정("나중에"로 보내기)은 `apply(to:)`로 그때의 값으로 돌린다.
struct ItemSnapshot {
    let id: UUID
    let title: String
    let body: String?
    let isTask: Bool
    let isAllDay: Bool
    let startDayKey: Int
    let endDayKey: Int
    let startDate: Date?
    let endDate: Date?
    let completedAt: Date?
    let inboxOrder: Double
    let hintDayCount: Int
    let hintStartMinute: Int
    let hintDurationMinutes: Int
    let reminderMask: Int
    let createdAt: Date
    let updatedAt: Date
    let category: ItemCategory?

    init(_ item: Item) {
        id = item.id
        title = item.title
        body = item.body
        isTask = item.isTask
        isAllDay = item.isAllDay
        startDayKey = item.startDayKey
        endDayKey = item.endDayKey
        startDate = item.startDate
        endDate = item.endDate
        completedAt = item.completedAt
        inboxOrder = item.inboxOrder
        hintDayCount = item.hintDayCount
        hintStartMinute = item.hintStartMinute
        hintDurationMinutes = item.hintDurationMinutes
        reminderMask = item.reminderMask
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        category = item.category
    }

    /// 남긴 값으로 되돌린다. 고친 시각만 지금으로 바꾼다(iCloud가 새 변경으로 받도록).
    func apply(to item: Item, now: Date = Date()) {
        item.id = id
        item.title = title
        item.body = body
        item.isTask = isTask
        item.isAllDay = isAllDay
        item.startDayKey = startDayKey
        item.endDayKey = endDayKey
        item.startDate = startDate
        item.endDate = endDate
        item.completedAt = completedAt
        item.inboxOrder = inboxOrder
        item.hintDayCount = hintDayCount
        item.hintStartMinute = hintStartMinute
        item.hintDurationMinutes = hintDurationMinutes
        item.reminderMask = reminderMask
        item.createdAt = createdAt
        item.updatedAt = now
        // 그 사이에 카테고리가 지워졌으면 카테고리 없음으로 둔다.
        item.category = category?.isDeleted == false ? category : nil
    }

    /// 지운 일정을 되살린 새 모델. 넣는 것(`insert`)은 부르는 쪽이 한다.
    func makeItem(now: Date = Date()) -> Item {
        let item = Item(title: title)
        apply(to: item, now: now)
        return item
    }
}
