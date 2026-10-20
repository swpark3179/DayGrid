import Foundation

/// 하루 상세 화면의 목록. 그 날에 걸친 일정을 세 묶음으로 나누고 순서를 정한다.
///
/// - `spanning`: 종일 일정과 여러 날에 걸친 일정. 먼저 시작한 것 → 긴 것 → 제목 순.
/// - `timed`: 그 날 안에 끝나는 시간 일정. 시작 시각 → 제목 순.
/// - `tasks`: 할일. 안 끝난 것 → 종일 → 시작 시각 → 제목 순.
///
/// 타임라인 보기(`separatingTimed`)에서는 시간이 있는 것을 모두 `timed`에 넣는다.
/// 시간을 정한 할일과 여러 날에 걸친 시간 일정도 포함하고, `spanning`과 `tasks`에는 종일인 것만 남는다.
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

    public static func make(on date: LocalDate, inputs: [Input], separatingTimed: Bool = false) -> DayAgenda {
        let covering = inputs.filter { $0.entry.startDay <= date && $0.entry.endDay >= date }

        func isTimed(_ input: Input) -> Bool {
            separatingTimed ? !input.entry.isAllDay : !input.isTask && input.entry.style == .chip
        }

        // 이 날 안에서 시작하는 시각. 전날부터 이어지면 0분이다.
        func startMinute(_ input: Input) -> Int {
            input.entry.startDay < date ? 0 : input.entry.startMinute ?? 0
        }

        let spanning = covering
            .filter { !$0.isTask && !isTimed($0) }
            .sorted { a, b in
                if a.entry.startDay != b.entry.startDay { return a.entry.startDay < b.entry.startDay }
                let aLength = a.entry.startDay.days(until: a.entry.endDay)
                let bLength = b.entry.startDay.days(until: b.entry.endDay)
                if aLength != bLength { return aLength > bLength }
                return tieBreak(a, b)
            }

        let timed = covering
            .filter(isTimed)
            .sorted { a, b in
                let aMinute = startMinute(a)
                let bMinute = startMinute(b)
                if aMinute != bMinute { return aMinute < bMinute }
                return tieBreak(a, b)
            }

        let tasks = covering
            .filter { $0.isTask && !isTimed($0) }
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
