import Foundation
import SwiftData

/// iCloud 동기화로 생기는 중복을 합친다.
///
/// - 카테고리: 기본 카테고리는 기기마다 같은 고정 `id`로 만들어진다. 새 기기나 다시 설치한 앱이 iCloud에서 받기 전에
///   기본값을 넣으면 같은 `id`가 둘이 된다. 가장 먼저 만든 것(사용자가 고친 이름·색이 남은 쪽)을 남기고,
///   나머지에 달린 일정과 반복 할일을 옮긴 뒤 지운다.
/// - 반복 할일 완료 기록: 두 기기에서 같은 주기를 체크하면 기록이 둘이 된다. 가장 이른 체크 하나만 남긴다.
///
/// 앱을 시작할 때와 iCloud에서 변경을 받은 뒤에 부른다.
@MainActor
enum DuplicateMerger {
    static func mergeAll(in context: ModelContext) {
        let mergedCategories = mergeCategories(in: context)
        let mergedCompletions = mergeCompletions(in: context)
        if mergedCategories + mergedCompletions > 0 {
            try? context.save()
        }
    }

    /// 지운 카테고리 수
    @discardableResult
    static func mergeCategories(in context: ModelContext) -> Int {
        let categories = (try? context.fetch(FetchDescriptor<ItemCategory>())) ?? []
        var removed = 0
        for group in Dictionary(grouping: categories, by: \.id).values where group.count > 1 {
            let ordered = group.sorted { ($0.createdAt, $0.sortOrder, $0.name) < ($1.createdAt, $1.sortOrder, $1.name) }
            let keeper = ordered[0]
            for duplicate in ordered.dropFirst() {
                for item in duplicate.items ?? [] {
                    item.category = keeper
                }
                for task in duplicate.recurringTasks ?? [] {
                    task.category = keeper
                }
                context.delete(duplicate)
                removed += 1
            }
        }
        return removed
    }

    /// 지운 완료 기록 수
    @discardableResult
    static func mergeCompletions(in context: ModelContext) -> Int {
        let completions = (try? context.fetch(FetchDescriptor<RecurrenceCompletion>())) ?? []
        var removed = 0
        let groups = Dictionary(grouping: completions) { completion in
            CompletionKey(taskID: completion.task?.id, cycleStartKey: completion.cycleStartKey)
        }
        for (key, group) in groups where key.taskID != nil && group.count > 1 {
            let ordered = group.sorted { ($0.completedDayKey, $0.completedAt) < ($1.completedDayKey, $1.completedAt) }
            for duplicate in ordered.dropFirst() {
                context.delete(duplicate)
                removed += 1
            }
        }
        return removed
    }

    private struct CompletionKey: Hashable {
        let taskID: UUID?
        let cycleStartKey: Int
    }
}
