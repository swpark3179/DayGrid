import Foundation

/// 앱 아이콘 배지: 날짜가 오늘이거나 이전인데 아직 끝내지 않은 할일 수(사용자 요청 2026-11-10).
///
/// - 입력은 미완료 할일의 시작일이다. 날짜 없는 "나중에" 할일, 완료한 할일, 할일이 아닌 일정, 반복 할일은 넣지 않는다.
///   반복 할일의 "남음" 표시는 잠금화면 원형 위젯이 맡는다.
/// - 기간 할일은 시작일로 한 번만 센다. 시작한 날부터 끝낼 때까지 배지에 남는다.
/// - 수는 자정에만 늘어난다(그날 시작하는 할일이 더해진다). 줄어드는 것은 체크하거나 지울 때뿐이다.
public enum TaskBadge {
    /// 자정에 배지 수가 바뀌는 날과 그날의 수
    public struct Change: Hashable, Sendable {
        public let day: LocalDate
        public let count: Int

        public init(day: LocalDate, count: Int) {
            self.day = day
            self.count = count
        }
    }

    /// `day`의 배지 수. 시작일이 `day`와 같거나 이전인 미완료 할일 수다. 0이면 배지를 숨긴다.
    public static func count(on day: LocalDate, undoneTaskDays: [LocalDate]) -> Int {
        undoneTaskDays.reduce(0) { $0 + ($1 <= day ? 1 : 0) }
    }

    /// `today` 다음 날부터 `end`(포함)까지, 배지 수가 바뀌는 날과 그날의 수.
    /// 그날 시작하는 미완료 할일이 있는 날만 들어간다. 앱이 꺼져 있어도 자정에 배지를 맞추는 데 쓴다.
    public static func changes(after today: LocalDate, through end: LocalDate, undoneTaskDays: [LocalDate]) -> [Change] {
        guard end > today else { return [] }
        let days = Set(undoneTaskDays.filter { $0 > today && $0 <= end }).sorted()
        return days.map { Change(day: $0, count: count(on: $0, undoneTaskDays: undoneTaskDays)) }
    }
}
