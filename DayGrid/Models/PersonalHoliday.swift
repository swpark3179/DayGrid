import DayGridCore
import Foundation
import SwiftData

/// 회사 휴가처럼 나만의 쉬는 날(하루 또는 기간). 달력에서 공휴일처럼 날짜를 빨갛게 표시한다.
@Model
final class PersonalHoliday {
    var id: UUID = UUID()
    var name: String = ""
    /// yyyymmdd
    var startDayKey: Int = 0
    /// yyyymmdd(포함)
    var endDayKey: Int = 0
    var createdAt: Date = Date()

    init(name: String, from start: LocalDate, through end: LocalDate) {
        self.name = name
        self.startDayKey = start.yyyymmdd
        self.endDayKey = max(start, end).yyyymmdd
    }
}

extension PersonalHoliday {
    var startDay: LocalDate? { LocalDate(yyyymmdd: startDayKey) }

    var endDay: LocalDate? { LocalDate(yyyymmdd: endDayKey) }

    func setDays(from start: LocalDate, through end: LocalDate) {
        startDayKey = start.yyyymmdd
        endDayKey = max(start, end).yyyymmdd
    }

    /// 달력 표시용 값. 날짜가 비어 있으면 `nil`.
    var mark: (name: String, start: LocalDate, end: LocalDate)? {
        guard let startDay else { return nil }
        return (name, startDay, endDay ?? startDay)
    }

    static func predicate(overlapping range: ClosedRange<LocalDate>) -> Predicate<PersonalHoliday> {
        let lower = range.lowerBound.yyyymmdd
        let upper = range.upperBound.yyyymmdd
        return #Predicate<PersonalHoliday> { holiday in
            holiday.startDayKey > 0 && holiday.startDayKey <= upper && holiday.endDayKey >= lower
        }
    }
}
