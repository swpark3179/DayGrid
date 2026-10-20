import Foundation

/// 하루 상세 타임라인의 배치. 시간 일정을 하루 안의 분 단위 구간으로 놓는다.
///
/// - 범위: 업무 시간을 기본으로 하고, 밖에 일정이 있으면 그 시각까지 넓힌다. 위아래 끝은 정시로 맞춘다.
/// - 블록: 너무 짧은 일정도 보이도록 최소 `minimumMinutes`만큼 그린다.
/// - 겹치는 일정은 묶음마다 열을 나눠 나란히 놓는다. 묶음은 그리는 구간이 이어지는 블록들이다.
public struct DayTimeline: Sendable, Equatable {
    public struct Input: Sendable, Equatable {
        public let id: UUID
        public let title: String
        /// 이 날 자정부터 지난 분.
        public let startMinute: Int
        /// 끝(포함하지 않음). 다음 날로 넘어가면 1440.
        public let endMinute: Int

        public init(id: UUID, title: String, startMinute: Int, endMinute: Int) {
            self.id = id
            self.title = title
            self.startMinute = startMinute
            self.endMinute = endMinute
        }

        /// `start..<end` 시간 일정 중 `date`에 걸친 부분. 그 날에 걸치지 않으면 `nil`.
        /// 전날부터 이어지면 0분부터, 다음 날로 넘어가면 1440분까지다.
        /// 끝이 자정 정각이면 다음 날에는 없다(`CalendarEntry.timed`와 같은 규칙).
        public init?(id: UUID, title: String, start: Date, end: Date, on date: LocalDate, timeZone: TimeZone = .current) {
            let dayStart = date.date(in: timeZone)
            let nextDayStart = date.adding(days: 1).date(in: timeZone)
            let end = max(start, end)
            // 0분짜리 일정은 시작한 날에만 있다.
            let isOnDay = end > start ? end > dayStart : start >= dayStart
            guard start < nextDayStart, isOnDay else { return nil }
            self.init(
                id: id,
                title: title,
                startMinute: start <= dayStart ? 0 : LocalDate.minuteOfDay(start, in: timeZone),
                endMinute: end >= nextDayStart ? DayTimeline.minutesPerDay : LocalDate.minuteOfDay(end, in: timeZone)
            )
        }
    }

    public struct Block: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let startMinute: Int
        /// 그리는 끝. 짧은 일정은 `minimumMinutes`까지 늘린다(하루 끝을 넘지 않는다).
        public let endMinute: Int
        /// 겹치는 묶음 안에서 몇째 열인지(0부터).
        public let column: Int
        /// 그 묶음의 열 수.
        public let columnCount: Int
    }

    public static let minutesPerDay = 1440
    /// 블록을 그리는 최소 길이(분).
    public static let minimumMinutes = 30

    /// 고친 업무 시간(자정부터 지난 분). 이 밖은 화면이 옅게 칠한다.
    public let workStart: Int
    public let workEnd: Int
    /// 그리는 범위. 둘 다 정시다.
    public let rangeStart: Int
    public let rangeEnd: Int
    /// 시작 → 긴 것 → 제목 순.
    public let blocks: [Block]

    /// 선을 긋는 정시(범위 양 끝 포함).
    public var hourMarks: [Int] {
        Array(stride(from: rangeStart, through: rangeEnd, by: 60))
    }

    public static func make(inputs: [Input], workStart: Int, workEnd: Int) -> DayTimeline {
        let work = normalizedWorkHours(start: workStart, end: workEnd)

        struct Span {
            let id: UUID
            let title: String
            let start: Int
            let end: Int
        }
        let spans = inputs
            .map { input -> Span in
                let start = min(max(input.startMinute, 0), minutesPerDay - 1)
                let end = min(max(input.endMinute, start + minimumMinutes), minutesPerDay)
                return Span(id: input.id, title: input.title, start: start, end: end)
            }
            .sorted { a, b in
                if a.start != b.start { return a.start < b.start }
                if a.end != b.end { return a.end > b.end }
                if a.title != b.title { return a.title < b.title }
                return a.id.uuidString < b.id.uuidString
            }

        var blocks: [Block] = []
        var cluster: [(span: Span, column: Int)] = []
        // 묶음 안 열마다 마지막 블록의 끝. 가장 큰 값이 묶음의 끝이다.
        var columnEnds: [Int] = []
        func closeCluster() {
            let count = columnEnds.count
            blocks += cluster.map { entry in
                Block(id: entry.span.id, startMinute: entry.span.start, endMinute: entry.span.end, column: entry.column, columnCount: count)
            }
            cluster = []
            columnEnds = []
        }
        for span in spans {
            if let clusterEnd = columnEnds.max(), span.start >= clusterEnd {
                closeCluster()
            }
            if let column = columnEnds.firstIndex(where: { $0 <= span.start }) {
                columnEnds[column] = span.end
                cluster.append((span: span, column: column))
            } else {
                columnEnds.append(span.end)
                cluster.append((span: span, column: columnEnds.count - 1))
            }
        }
        closeCluster()

        let earliest = blocks.map(\.startMinute).min() ?? work.start
        let latest = blocks.map(\.endMinute).max() ?? work.end
        return DayTimeline(
            workStart: work.start,
            workEnd: work.end,
            rangeStart: min(work.start, earliest) / 60 * 60,
            rangeEnd: (max(work.end, latest) + 59) / 60 * 60,
            blocks: blocks
        )
    }

    /// 업무 시간을 하루 안으로 맞춘다. 끝이 시작보다 늦지 않으면 시작 + 1시간으로 한다.
    public static func normalizedWorkHours(start: Int, end: Int) -> (start: Int, end: Int) {
        let start = min(max(start, 0), minutesPerDay - 60)
        var end = min(max(end, 0), minutesPerDay)
        if end <= start {
            end = start + 60
        }
        return (start, end)
    }

    /// 높이가 `height`인 타임라인에서 위로부터 `y`인 곳의 시각. `step`분 단위로 내리고 범위 안으로 맞춘다.
    /// 빈 곳을 눌러 새 일정을 만들 때 쓴다.
    public func minute(atY y: Double, height: Double, step: Int = 30) -> Int {
        guard height > 0 else { return rangeStart }
        let minute = Double(rangeStart) + y * Double(rangeEnd - rangeStart) / height
        let floored = Int((minute / Double(step)).rounded(.down)) * step
        return min(max(floored, rangeStart), rangeEnd - step)
    }

    /// 높이가 `height`인 타임라인에서 `minute`의 위치.
    public func y(ofMinute minute: Int, height: Double) -> Double {
        Double(minute - rangeStart) * height / Double(rangeEnd - rangeStart)
    }
}
