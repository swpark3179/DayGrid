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
}
