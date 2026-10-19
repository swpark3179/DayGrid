import Foundation
import Testing
@testable import DayGridCore

private func day(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
    LocalDate(year: year, month: month, day: day)!
}

/// 테스트에서 순서가 정해진 UUID. 숫자가 작을수록 uuidString도 앞선다.
private func uuid(_ number: Int) -> UUID {
    let digits = String(number)
    let suffix = String(repeating: "0", count: 12 - digits.count) + digits
    return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
}

private func allDay(_ id: Int, _ start: LocalDate, _ end: LocalDate? = nil) -> CalendarEntry {
    .allDay(id: uuid(id), from: start, through: end ?? start)
}

private func chip(_ id: Int, _ date: LocalDate, minute: Int) -> CalendarEntry {
    CalendarEntry(id: uuid(id), startDay: date, endDay: date, isAllDay: false, startMinute: minute)
}

private extension MonthGrid {
    func week(containing date: LocalDate) -> Week {
        weeks.first { week in week.days.contains { $0.date == date } }!
    }

    func segments(of id: Int) -> [Segment] {
        weeks.flatMap(\.segments).filter { $0.entryID == uuid(id) }
    }
}

private extension MonthGrid.Week {
    func segment(_ id: Int) -> MonthGrid.Segment? {
        segments.first { $0.entryID == uuid(id) }
    }

    func hiddenCount(on date: LocalDate) -> Int {
        days.first { $0.date == date }!.hiddenCount
    }
}

@Suite("MonthLayout 주 구성")
struct MonthLayoutWeekTests {
    @Test func october2026StartingSunday() {
        let grid = MonthLayout.make(month: day(2026, 10, 19), firstWeekday: 1, entries: [], maxVisibleLanes: 3)
        #expect(grid.firstDayOfMonth == day(2026, 10, 1))
        #expect(grid.weeks.count == 5)
        #expect(grid.weeks.first?.days.first?.date == day(2026, 9, 27))
        #expect(grid.weeks.last?.days.last?.date == day(2026, 10, 31))
        #expect(grid.weeks.allSatisfy { $0.days.count == 7 })
        let firstWeek = grid.weeks[0].days
        #expect(firstWeek.prefix(4).allSatisfy { !$0.isInMonth })
        #expect(firstWeek.suffix(3).allSatisfy(\.isInMonth))
    }

    @Test func october2026StartingMonday() {
        let range = MonthLayout.visibleDays(of: day(2026, 10, 1), firstWeekday: 2)
        #expect(range == day(2026, 9, 28)...day(2026, 11, 1))
        let grid = MonthLayout.make(month: day(2026, 10, 1), firstWeekday: 2, entries: [], maxVisibleLanes: 3)
        #expect(grid.weeks.count == 5)
        #expect(grid.weeks.allSatisfy { $0.days[0].date.weekday == 2 })
    }

    @Test func february2026FitsInFourWeeks() {
        let range = MonthLayout.visibleDays(of: day(2026, 2, 14))
        #expect(range == day(2026, 2, 1)...day(2026, 2, 28))
        #expect(MonthLayout.make(month: day(2026, 2, 14), entries: [], maxVisibleLanes: 3).weeks.count == 4)
    }

    @Test func august2026NeedsSixWeeks() {
        let range = MonthLayout.visibleDays(of: day(2026, 8, 1))
        #expect(range == day(2026, 7, 26)...day(2026, 9, 5))
        #expect(MonthLayout.make(month: day(2026, 8, 1), entries: [], maxVisibleLanes: 3).weeks.count == 6)
    }

    @Test func invalidFirstWeekdayFallsBackToSunday() {
        #expect(MonthLayout.visibleDays(of: day(2026, 10, 1), firstWeekday: 9) == MonthLayout.visibleDays(of: day(2026, 10, 1)))
    }
}

@Suite("MonthLayout 조각과 레인")
struct MonthLayoutSegmentTests {
    @Test func multiDayEntryInsideOneWeek() {
        let grid = MonthLayout.make(month: day(2026, 10, 1), entries: [allDay(1, day(2026, 10, 12), day(2026, 10, 16))], maxVisibleLanes: 3)
        let segments = grid.segments(of: 1)
        #expect(segments.count == 1)
        let segment = segments[0]
        #expect(segment.startColumn == 1)
        #expect(segment.length == 5)
        #expect(segment.lane == 0)
        #expect(segment.style == .bar)
        #expect(!segment.continuesFromPreviousWeek)
        #expect(!segment.continuesToNextWeek)
    }

    @Test func entrySplitAcrossWeeks() {
        let grid = MonthLayout.make(month: day(2026, 10, 1), entries: [allDay(1, day(2026, 10, 9), day(2026, 10, 13))], maxVisibleLanes: 3)
        let first = grid.week(containing: day(2026, 10, 9)).segment(1)!
        let second = grid.week(containing: day(2026, 10, 13)).segment(1)!
        #expect([first.startColumn, first.length] == [5, 2])
        #expect(!first.continuesFromPreviousWeek && first.continuesToNextWeek)
        #expect([second.startColumn, second.length] == [0, 3])
        #expect(second.continuesFromPreviousWeek && !second.continuesToNextWeek)
    }

    @Test func entryCrossingMonthBoundaryAppearsInBothMonths() {
        let trip = allDay(1, day(2026, 10, 28), day(2026, 11, 3))
        let october = MonthLayout.make(month: day(2026, 10, 1), entries: [trip], maxVisibleLanes: 3)
        let november = MonthLayout.make(month: day(2026, 11, 1), entries: [trip], maxVisibleLanes: 3)

        let inOctober = october.segments(of: 1)
        #expect(inOctober.count == 1)
        #expect([inOctober[0].startColumn, inOctober[0].length] == [3, 4])
        #expect(inOctober[0].continuesToNextWeek)

        let inNovember = november.segments(of: 1)
        #expect(inNovember.count == 1)
        #expect([inNovember[0].startColumn, inNovember[0].length] == [0, 3])
        #expect(inNovember[0].continuesFromPreviousWeek)
    }

    @Test func overlappingEntriesGetSeparateLanesAndFreeLanesAreReused() {
        let sprint = allDay(1, day(2026, 10, 12), day(2026, 10, 16))
        let dinner = chip(2, day(2026, 10, 14), minute: 19 * 60)
        let saturday = chip(3, day(2026, 10, 17), minute: 10 * 60)
        let week = MonthLayout.make(month: day(2026, 10, 1), entries: [dinner, saturday, sprint], maxVisibleLanes: 4)
            .week(containing: day(2026, 10, 14))
        #expect(week.segment(1)?.lane == 0)
        #expect(week.segment(2)?.lane == 1)
        #expect(week.segment(2)?.style == .chip)
        #expect(week.segment(3)?.lane == 0)
    }

    @Test func barsComeBeforeChipsAndChipsAreOrderedByTime() {
        let date = day(2026, 10, 19)
        let entries = [chip(1, date, minute: 16 * 60), chip(2, date, minute: 10 * 60), allDay(3, date), chip(4, date, minute: 12 * 60 + 30)]
        let week = MonthLayout.make(month: date, entries: entries, maxVisibleLanes: 5).week(containing: date)
        #expect(week.segment(3)?.lane == 0)
        #expect(week.segment(2)?.lane == 1)
        #expect(week.segment(4)?.lane == 2)
        #expect(week.segment(1)?.lane == 3)
    }

    @Test func longerEntriesStartingTheSameDayGoFirst() {
        let short = allDay(1, day(2026, 10, 12))
        let long = allDay(2, day(2026, 10, 12), day(2026, 10, 15))
        let week = MonthLayout.make(month: day(2026, 10, 1), entries: [short, long], maxVisibleLanes: 3)
            .week(containing: day(2026, 10, 12))
        #expect(week.segment(2)?.lane == 0)
        #expect(week.segment(1)?.lane == 1)
    }

    @Test func layoutDoesNotDependOnInputOrder() {
        let date = day(2026, 10, 30)
        let entries = [
            allDay(1, day(2026, 10, 28), day(2026, 11, 3)),
            allDay(2, date),
            chip(3, date, minute: 9 * 60),
            chip(4, date, minute: 15 * 60),
            chip(5, date, minute: 19 * 60),
            allDay(6, day(2026, 10, 26), day(2026, 10, 27)),
        ]
        let expected = MonthLayout.make(month: date, entries: entries, maxVisibleLanes: 3)
        #expect(MonthLayout.make(month: date, entries: entries.reversed(), maxVisibleLanes: 3) == expected)
        #expect(MonthLayout.make(month: date, entries: [entries[3], entries[0], entries[5], entries[2], entries[4], entries[1]], maxVisibleLanes: 3) == expected)
    }

    @Test func entriesOutsideTheVisibleRangeAreIgnored() {
        let grid = MonthLayout.make(
            month: day(2026, 10, 1),
            entries: [allDay(1, day(2026, 12, 25)), allDay(2, day(2026, 9, 1), day(2026, 9, 26)), allDay(3, day(2026, 9, 26), day(2026, 9, 27))],
            maxVisibleLanes: 3
        )
        #expect(grid.segments(of: 1).isEmpty)
        #expect(grid.segments(of: 2).isEmpty)
        #expect(grid.segments(of: 3).count == 1)
        #expect(grid.segments(of: 3).first?.continuesFromPreviousWeek == true)
    }
}

@Suite("MonthLayout 넘침")
struct MonthLayoutOverflowTests {
    @Test func busyDayShowsPlusCount() {
        // 10/30(금): 출장 막대(10/28–11/3) + 종일 1 + 시간 3 = 5개, 보이는 줄 3개
        let date = day(2026, 10, 30)
        let entries = [
            allDay(1, day(2026, 10, 28), day(2026, 11, 3)),
            allDay(2, date),
            chip(3, date, minute: 9 * 60),
            chip(4, date, minute: 15 * 60),
            chip(5, date, minute: 19 * 60),
        ]
        let week = MonthLayout.make(month: date, entries: entries, maxVisibleLanes: 3).week(containing: date)
        #expect(Set(week.segments.map(\.entryID)) == Set([uuid(1), uuid(2)]))
        #expect(week.hiddenCount(on: date) == 3)
        #expect(week.hiddenCount(on: day(2026, 10, 29)) == 0)
        #expect(week.hiddenCount(on: day(2026, 10, 31)) == 0)
    }

    @Test func lastLaneBarTouchingAnOverflowDayIsHiddenOnEveryDay() {
        let a = allDay(1, day(2026, 10, 13), day(2026, 10, 15))
        let b = allDay(2, day(2026, 10, 13), day(2026, 10, 15))
        let c = allDay(3, day(2026, 10, 13), day(2026, 10, 15))
        let d = chip(4, day(2026, 10, 15), minute: 9 * 60)
        let week = MonthLayout.make(month: day(2026, 10, 1), entries: [a, b, c, d], maxVisibleLanes: 3)
            .week(containing: day(2026, 10, 13))
        #expect(week.segment(3) == nil)
        #expect(week.segment(4) == nil)
        #expect(Set(week.segments.map(\.entryID)) == Set([uuid(1), uuid(2)]))
        #expect(week.hiddenCount(on: day(2026, 10, 13)) == 1)
        #expect(week.hiddenCount(on: day(2026, 10, 14)) == 1)
        #expect(week.hiddenCount(on: day(2026, 10, 15)) == 2)
        #expect(week.hiddenCount(on: day(2026, 10, 16)) == 0)
    }

    @Test func exactlyFullDayHidesNothing() {
        let date = day(2026, 10, 19)
        let entries = [allDay(1, date), chip(2, date, minute: 600), chip(3, date, minute: 700)]
        let week = MonthLayout.make(month: date, entries: entries, maxVisibleLanes: 3).week(containing: date)
        #expect(week.segments.count == 3)
        #expect(week.hiddenCount(on: date) == 0)
    }

    @Test func singleVisibleLane() {
        let date = day(2026, 10, 19)
        let quiet = day(2026, 10, 20)
        let entries = [chip(1, date, minute: 600), chip(2, date, minute: 700), chip(3, quiet, minute: 600)]
        let week = MonthLayout.make(month: date, entries: entries, maxVisibleLanes: 1).week(containing: date)
        #expect(week.segments.map(\.entryID) == [uuid(3)])
        #expect(week.hiddenCount(on: date) == 2)
        #expect(week.hiddenCount(on: quiet) == 0)
    }

    @Test func nonPositiveLaneLimitActsLikeOne() {
        let date = day(2026, 10, 19)
        let entries = [chip(1, date, minute: 600)]
        #expect(MonthLayout.make(month: date, entries: entries, maxVisibleLanes: 0) == MonthLayout.make(month: date, entries: entries, maxVisibleLanes: 1))
    }
}

@Suite("CalendarEntry")
struct CalendarEntryTests {
    private let seoul = TimeZone(secondsFromGMT: 9 * 3600)!

    private func instant(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoul
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func timedEntryWithinOneDayIsAChip() {
        let entry = CalendarEntry.timed(id: uuid(1), start: instant(2026, 10, 19, 9, 30), end: instant(2026, 10, 19, 10, 30), timeZone: seoul)
        #expect(entry.startDay == day(2026, 10, 19))
        #expect(entry.endDay == day(2026, 10, 19))
        #expect(entry.startMinute == 9 * 60 + 30)
        #expect(entry.style == .chip)
    }

    @Test func endingExactlyAtMidnightStaysOnTheStartDay() {
        let entry = CalendarEntry.timed(id: uuid(1), start: instant(2026, 10, 19, 22), end: instant(2026, 10, 20, 0), timeZone: seoul)
        #expect(entry.endDay == day(2026, 10, 19))
        #expect(entry.style == .chip)
    }

    @Test func crossingMidnightBecomesABar() {
        let entry = CalendarEntry.timed(id: uuid(1), start: instant(2026, 10, 19, 23), end: instant(2026, 10, 20, 1), timeZone: seoul)
        #expect(entry.endDay == day(2026, 10, 20))
        #expect(entry.style == .bar)
    }

    @Test func endBeforeStartIsClampedToStartDay() {
        let entry = CalendarEntry.timed(id: uuid(1), start: instant(2026, 10, 19, 15), end: instant(2026, 10, 18, 9), timeZone: seoul)
        #expect(entry.endDay == entry.startDay)
        #expect(entry.style == .chip)
    }

    @Test func timeZoneDecidesTheDay() {
        let start = instant(2026, 10, 19, 8) // 서울 08:00 = UTC 전날 23:00
        let utc = TimeZone(secondsFromGMT: 0)!
        let entry = CalendarEntry.timed(id: uuid(1), start: start, end: start.addingTimeInterval(3600), timeZone: utc)
        #expect(entry.startDay == day(2026, 10, 18))
        #expect(entry.endDay == day(2026, 10, 19))
        #expect(entry.startMinute == 23 * 60)
        #expect(entry.style == .bar)
    }

    @Test func singleAllDayEntryIsABar() {
        #expect(allDay(1, day(2026, 10, 19)).style == .bar)
        #expect(CalendarEntry(id: uuid(1), startDay: day(2026, 10, 19), endDay: day(2026, 10, 1), isAllDay: true).endDay == day(2026, 10, 19))
    }
}
