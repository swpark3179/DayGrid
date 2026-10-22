extension LocalDate {
    /// `weekday`(1 = 일요일)에 대응하는 한 글자 요일.
    public static let koreanWeekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    /// "월"
    public var koreanWeekdaySymbol: String {
        Self.koreanWeekdaySymbols[weekday - 1]
    }

    /// "2026년 10월"
    public var koreanMonthTitle: String {
        "\(year)년 \(month)월"
    }

    /// "2026년 10월 19일 (월)"
    public var koreanLongText: String {
        "\(year)년 \(month)월 \(day)일 (\(koreanWeekdaySymbol))"
    }

    /// "10월 19일"
    public var koreanMonthDayText: String {
        "\(month)월 \(day)일"
    }

    /// "10월 19일 (월)"
    public var koreanMonthDayWeekdayText: String {
        "\(month)월 \(day)일 (\(koreanWeekdaySymbol))"
    }

    /// 꾹 눌러 고르는 기간의 표시. 순서와 상관없이 앞 날짜부터 쓰고, 같은 달이면 뒤 날짜의 달을 뺀다.
    /// 예: "10월 12일 · 하루", "10월 12일 – 16일 · 5일", "10월 30일 – 11월 2일 · 4일"
    public func koreanRangeText(through other: LocalDate) -> String {
        let start = Swift.min(self, other)
        let end = Swift.max(self, other)
        guard start != end else { return "\(start.koreanMonthDayText) · 하루" }
        let endText = start.year == end.year && start.month == end.month ? "\(end.day)일" : end.koreanMonthDayText
        return "\(start.koreanMonthDayText) – \(endText) · \(start.days(until: end) + 1)일"
    }
}
