import Foundation

/// 월간 달력 한 페이지의 배치 결과.
public struct MonthGrid: Sendable, Equatable {
    public let firstDayOfMonth: LocalDate
    /// 그 달 1일이 들어간 주부터 말일이 들어간 주까지(4~6주).
    public let weeks: [Week]

    public struct Week: Sendable, Equatable, Identifiable {
        /// 7일, 주 시작 요일부터.
        public let days: [Day]
        /// 화면에 그릴 조각. 공간이 없어 숨긴 조각은 들어 있지 않다.
        public let segments: [Segment]

        public var id: LocalDate { days[0].date }
    }

    public struct Day: Sendable, Equatable, Identifiable {
        public let date: LocalDate
        public let isInMonth: Bool
        /// 이 날에 걸쳐 있지만 공간이 없어 숨긴 일정 수. 0보다 크면 마지막 줄에 "+N"을 그린다.
        public let hiddenCount: Int

        public var id: LocalDate { date }
    }

    /// 한 주 안에 들어가는 일정 조각. 한 일정은 주마다 조각 하나가 된다.
    public struct Segment: Sendable, Equatable, Identifiable {
        public let entryID: UUID
        public let style: CalendarEntry.Style
        /// 0...6
        public let startColumn: Int
        /// 1...7
        public let length: Int
        /// 0부터 위에서 아래로.
        public let lane: Int
        public let continuesFromPreviousWeek: Bool
        public let continuesToNextWeek: Bool

        public var id: UUID { entryID }

        var columns: Range<Int> { startColumn..<(startColumn + length) }
    }
}

public enum MonthLayout {
    /// `month`가 속한 달을 달력에 그릴 때 보이는 날짜 범위(앞뒤 달의 날짜 포함).
    /// - Parameter firstWeekday: 주 시작 요일. 1 = 일요일, 2 = 월요일 …
    public static func visibleDays(of month: LocalDate, firstWeekday: Int = 1) -> ClosedRange<LocalDate> {
        let weekStart = (1...7).contains(firstWeekday) ? firstWeekday : 1
        let first = month.firstDayOfMonth
        let last = month.lastDayOfMonth
        let weekEnd = (weekStart + 5) % 7 + 1
        let gridStart = first.adding(days: -((first.weekday - weekStart + 7) % 7))
        let gridEnd = last.adding(days: (weekEnd - last.weekday + 7) % 7)
        return gridStart...gridEnd
    }

    /// `month`가 속한 달의 배치를 만든다.
    ///
    /// - 일정은 주 단위 조각으로 잘린다.
    /// - 조각은 시작 열 → 긴 것 → 막대 → 시작 시각 → id 순으로, 걸친 열이 모두 빈 가장 낮은 레인에 놓인다.
    /// - 보이는 줄이 `maxVisibleLanes`(L)개일 때, 레인 L 이상 조각이 걸친 날은 "넘친 날"이다.
    ///   레인 L-1 미만 조각은 항상 보이고, 레인 L-1 조각은 걸친 날 중 넘친 날이 없을 때만 보인다.
    ///   나머지는 숨기고 날짜별 `hiddenCount`로 센다.
    public static func make(
        month: LocalDate,
        firstWeekday: Int = 1,
        entries: [CalendarEntry],
        maxVisibleLanes: Int
    ) -> MonthGrid {
        let range = visibleDays(of: month, firstWeekday: firstWeekday)
        let laneLimit = max(1, maxVisibleLanes)
        let relevant = entries.filter { $0.startDay <= range.upperBound && $0.endDay >= range.lowerBound }

        let weeks = stride(from: range.lowerBound, through: range.upperBound, by: 7).map { weekStart in
            makeWeek(starting: weekStart, month: month, entries: relevant, laneLimit: laneLimit)
        }
        return MonthGrid(firstDayOfMonth: month.firstDayOfMonth, weeks: weeks)
    }

    private static func makeWeek(
        starting weekStart: LocalDate,
        month: LocalDate,
        entries: [CalendarEntry],
        laneLimit: Int
    ) -> MonthGrid.Week {
        let weekEnd = weekStart.adding(days: 6)

        let pieces = entries
            .filter { $0.startDay <= weekEnd && $0.endDay >= weekStart }
            .map { entry in
                let first = max(entry.startDay, weekStart)
                let last = min(entry.endDay, weekEnd)
                return Piece(
                    entry: entry,
                    startColumn: weekStart.days(until: first),
                    length: first.days(until: last) + 1,
                    continuesFromPreviousWeek: entry.startDay < weekStart,
                    continuesToNextWeek: entry.endDay > weekEnd
                )
            }
            .sorted(by: Piece.placementOrder)

        // 탐욕 레인 배치: 걸친 열이 모두 비어 있는 가장 낮은 레인.
        var occupied: [[Bool]] = []
        var placed: [MonthGrid.Segment] = []
        for piece in pieces {
            let columns = piece.startColumn..<(piece.startColumn + piece.length)
            var lane = 0
            while lane < occupied.count, columns.contains(where: { occupied[lane][$0] }) {
                lane += 1
            }
            if lane == occupied.count {
                occupied.append(Array(repeating: false, count: 7))
            }
            for column in columns {
                occupied[lane][column] = true
            }
            placed.append(MonthGrid.Segment(
                entryID: piece.entry.id,
                style: piece.entry.style,
                startColumn: piece.startColumn,
                length: piece.length,
                lane: lane,
                continuesFromPreviousWeek: piece.continuesFromPreviousWeek,
                continuesToNextWeek: piece.continuesToNextWeek
            ))
        }

        // 넘침 처리
        var overflowColumns = Set<Int>()
        for segment in placed where segment.lane >= laneLimit {
            overflowColumns.formUnion(segment.columns)
        }
        func isVisible(_ segment: MonthGrid.Segment) -> Bool {
            if segment.lane < laneLimit - 1 { return true }
            return segment.lane == laneLimit - 1 && !segment.columns.contains { overflowColumns.contains($0) }
        }
        let visible = placed.filter(isVisible)
        var hiddenCounts = Array(repeating: 0, count: 7)
        for segment in placed where !isVisible(segment) {
            for column in segment.columns {
                hiddenCounts[column] += 1
            }
        }

        let days = (0..<7).map { offset in
            let date = weekStart.adding(days: offset)
            return MonthGrid.Day(
                date: date,
                isInMonth: date.year == month.year && date.month == month.month,
                hiddenCount: hiddenCounts[offset]
            )
        }
        return MonthGrid.Week(days: days, segments: visible)
    }

    private struct Piece {
        let entry: CalendarEntry
        let startColumn: Int
        let length: Int
        let continuesFromPreviousWeek: Bool
        let continuesToNextWeek: Bool

        static func placementOrder(_ a: Piece, _ b: Piece) -> Bool {
            if a.startColumn != b.startColumn { return a.startColumn < b.startColumn }
            if a.length != b.length { return a.length > b.length }
            let aIsBar = a.entry.style == .bar
            let bIsBar = b.entry.style == .bar
            if aIsBar != bIsBar { return aIsBar }
            let aMinute = a.entry.startMinute ?? -1
            let bMinute = b.entry.startMinute ?? -1
            if aMinute != bMinute { return aMinute < bMinute }
            return a.entry.id.uuidString < b.entry.id.uuidString
        }
    }
}
