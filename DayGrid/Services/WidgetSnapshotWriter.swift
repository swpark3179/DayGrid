import DayGridCore
import Foundation
import SwiftData
import WidgetKit

/// 잠금화면 위젯(남은 반복 할일)에 넘길 요약을 App Group 폴더에 쓰고, 위젯을 다시 그리게 한다.
///
/// 쓰는 시점: 앱 시작과 포그라운드 진입, 데이터 저장(1초 모음), iCloud에서 받은 뒤, 알림의 "완료" 뒤.
/// App Group이 없는 빌드(CI 시뮬레이터)에서는 조용히 넘어간다.
@MainActor
final class WidgetSnapshotWriter {
    static let shared = WidgetSnapshotWriter()

    /// 앱이 만든 저장소
    var container: ModelContainer?

    private var pendingWrite: Task<Void, Never>?
    private var lastEntries: [RecurringSnapshot.Entry]?

    static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: RecurringSnapshot.appGroupID)?
            .appending(path: RecurringSnapshot.fileName)
    }

    /// 잠깐 모았다가 한 번만 쓴다(저장이 연달아 일어날 때).
    func scheduleWrite(after delay: Duration = .seconds(1)) {
        pendingWrite?.cancel()
        pendingWrite = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            write()
        }
    }

    func write(now: Date = Date()) {
        guard let context = container?.mainContext, let url = Self.snapshotURL else { return }
        let snapshot = Self.makeSnapshot(in: context, now: now)
        // 내용이 같으면 위젯을 다시 그리지 않는다(만든 시각만 다르다).
        guard snapshot.entries != lastEntries, let data = try? snapshot.encoded() else { return }
        do {
            try data.write(to: url, options: .atomic)
            lastEntries = snapshot.entries
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // 다음 저장 때 다시 쓴다.
        }
    }

    /// 사용 중인 반복 할일의 요약. 순서는 반복 탭과 같다(정렬 순서, 만든 순서).
    static func makeSnapshot(in context: ModelContext, now: Date = Date(), timeZone: TimeZone = .current) -> RecurringSnapshot {
        let descriptor = FetchDescriptor<RecurringTask>(
            predicate: RecurringTask.activePredicate,
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        let tasks = (try? context.fetch(descriptor)) ?? []
        return RecurringSnapshot.make(
            generatedAt: now,
            today: LocalDate(now, in: timeZone),
            tasks: tasks.compactMap { task -> (id: UUID, title: String, recurrence: Recurrence, completedCycleStarts: Set<LocalDate>)? in
                guard let recurrence = task.recurrence else { return nil }
                return (task.id, task.title, recurrence, Set(task.completionDays.keys))
            }
        )
    }
}
