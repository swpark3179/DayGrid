import Foundation

/// 하루 상세 화면의 목록. 그 날에 걸친 일정을 세 묶음으로 나누고 순서를 정한다.
///
/// - `spanning`: 종일 일정과 여러 날에 걸친 일정. 먼저 시작한 것 → 긴 것 → 제목 순.
/// - `timed`: 그 날 안에 끝나는 시간 일정. 시작 시각 → 제목 순.
/// - `tasks`: 할일. 안 끝난 것 → 종일 → 시작 시각 → 제목 순.
public struct DayAgenda: Sendable, Equatable {
    public struct Input: Sendable {
        public let entry: CalendarEntry
        public let title: String
        public let isTask: Bool
        public let isCompleted: Bool

        public init(entry: CalendarEntry, title: String, isTask: Bool = false, isCompleted: Bool = false) {
            self.entry = entry
            self.title = title
            self.isTask = isTask
            self.isCompleted = isCompleted
        }
    }

    public struct Row: Sendable, Equatable, Identifiable {
        public let id: UUID
        /// 여러 날 일정에서 이 날이 몇째 날인지(1부터).
        public let dayNumber: Int
        /// 일정 전체 일수. 하루짜리면 1.
        public let totalDays: Int
    }

    public let date: LocalDate
    public let spanning: [Row]
    public let timed: [Row]
    public let tasks: [Row]

    public var isEmpty: Bool {
        spanning.isEmpty && timed.isEmpty && tasks.isEmpty
    }

    public static func make(on date: LocalDate, inputs: [Input]) -> DayAgenda {
        let covering = inputs.filter { $0.entry.startDay <= date && $0.entry.endDay >= date }

        let spanning = covering
            .filter { !$0.isTask && $0.entry.style == .bar }
            .sorted { a, b in
                if a.entry.startDay != b.entry.startDay { return a.entry.startDay < b.entry.startDay }
                let aLength = a.entry.startDay.days(until: a.entry.endDay)
                let bLength = b.entry.startDay.days(until: b.entry.endDay)
                if aLength != bLength { return aLength > bLength }
                return tieBreak(a, b)
            }

        let timed = covering
            .filter { !$0.isTask && $0.entry.style == .chip }
            .sorted { a, b in
                let aMinute = a.entry.startMinute ?? 0
                let bMinute = b.entry.startMinute ?? 0
                if aMinute != bMinute { return aMinute < bMinute }
                return tieBreak(a, b)
            }

        let tasks = covering
            .filter(\.isTask)
            .sorted { a, b in
                if a.isCompleted != b.isCompleted { return !a.isCompleted }
                if a.entry.isAllDay != b.entry.isAllDay { return a.entry.isAllDay }
                let aMinute = a.entry.startMinute ?? 0
                let bMinute = b.entry.startMinute ?? 0
                if aMinute != bMinute { return aMinute < bMinute }
                return tieBreak(a, b)
            }

        func rows(_ inputs: [Input]) -> [Row] {
            inputs.map { input in
                Row(
                    id: input.entry.id,
                    dayNumber: input.entry.startDay.days(until: date) + 1,
                    totalDays: input.entry.startDay.days(until: input.entry.endDay) + 1
                )
            }
        }
        return DayAgenda(date: date, spanning: rows(spanning), timed: rows(timed), tasks: rows(tasks))
    }

    private static func tieBreak(_ a: Input, _ b: Input) -> Bool {
        if a.title != b.title { return a.title < b.title }
        return a.entry.id.uuidString < b.entry.id.uuidString
    }
}
