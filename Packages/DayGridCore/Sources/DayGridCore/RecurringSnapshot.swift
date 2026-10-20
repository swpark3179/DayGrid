import Foundation

/// 잠금화면 위젯에 넘기는 반복 할일 요약. 앱이 App Group 폴더에 JSON으로 쓰고, 위젯이 읽는다.
///
/// 위젯은 SwiftData 저장소를 열지 않는다. 대신 이 요약(규칙과 최근 완료 기록)으로 날짜마다 `Recurrence.isDue`를
/// 다시 계산하므로, 자정이 지나 새 주기가 와도 앱을 열지 않고 목록이 바뀐다.
public struct RecurringSnapshot: Codable, Hashable, Sendable {
    /// 앱과 위젯이 같이 쓰는 App Group
    public static let appGroupID = "group.io.github.swpark3179.DayGrid"
    public static let fileName = "recurring.json"
    /// 위젯을 누르면 여는 주소. 앱은 이 주소를 받으면 "반복" 탭을 연다.
    public static let openURL = URL(string: "daygrid://recurring")!
    /// 이만큼 지난 완료 기록은 넣지 않는다(지금과 앞으로 며칠의 주기 판단에는 필요 없다).
    public static let completionLookbackDays = 62

    public struct Entry: Codable, Hashable, Sendable {
        public let id: UUID
        public let title: String
        public let recurrence: Recurrence
        /// 완료한 주기의 시작일(오래된 것부터)
        public let completedCycleStarts: [LocalDate]

        public init(id: UUID, title: String, recurrence: Recurrence, completedCycleStarts: [LocalDate]) {
            self.id = id
            self.title = title
            self.recurrence = recurrence
            self.completedCycleStarts = completedCycleStarts
        }
    }

    public var generatedAt: Date
    /// 반복 탭과 같은 순서
    public var entries: [Entry]

    public init(generatedAt: Date, entries: [Entry]) {
        self.generatedAt = generatedAt
        self.entries = entries
    }

    /// `today` 기준으로 넣을 완료 기록만 남긴 요약.
    public static func make(
        generatedAt: Date,
        today: LocalDate,
        tasks: [(id: UUID, title: String, recurrence: Recurrence, completedCycleStarts: Set<LocalDate>)]
    ) -> RecurringSnapshot {
        let oldest = today.adding(days: -completionLookbackDays)
        return RecurringSnapshot(
            generatedAt: generatedAt,
            entries: tasks.map { task in
                Entry(
                    id: task.id,
                    title: task.title,
                    recurrence: task.recurrence,
                    completedCycleStarts: task.completedCycleStarts.filter { $0 >= oldest }.sorted()
                )
            }
        )
    }

    /// `day`에 주기가 돌아왔는데 아직 하지 않은 반복 할일
    public func pending(on day: LocalDate) -> [Entry] {
        entries.filter { $0.recurrence.isDue(on: day, completedCycleStarts: Set($0.completedCycleStarts)) }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> RecurringSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecurringSnapshot.self, from: data)
    }
}
