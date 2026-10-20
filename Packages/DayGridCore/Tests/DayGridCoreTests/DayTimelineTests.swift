import Foundation
import Testing
@testable import DayGridCore

private func day(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
    LocalDate(year: year, month: month, day: day)!
}

private func uuid(_ number: Int) -> UUID {
    let digits = String(number)
    let suffix = String(repeating: "0", count: 12 - digits.count) + digits
    return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
}

private let seoul = TimeZone(secondsFromGMT: 9 * 3600)!

/// `h:mm`부터 `minutes`분짜리 입력.
private func input(_ id: Int, _ title: String, _ hour: Int, _ minute: Int = 0, minutes: Int = 60) -> DayTimeline.Input {
    let start = hour * 60 + minute
    return DayTimeline.Input(id: uuid(id), title: title, startMinute: start, endMinute: start + minutes)
}

@Suite("DayTimeline")
struct DayTimelineTests {
    @Test func rangeIsTheWorkdayWhenEverythingFits() {
        let timeline = DayTimeline.make(inputs: [input(1, "주간 회의", 10), input(2, "은행 업무", 16)], workStart: 540, workEnd: 1080)
        #expect(timeline.rangeStart == 540)
        #expect(timeline.rangeEnd == 1080)
        #expect(timeline.hourMarks == [540, 600, 660, 720, 780, 840, 900, 960, 1020, 1080])
        #expect(timeline.blocks.map(\.id) == [uuid(1), uuid(2)])
        #expect(timeline.blocks.map(\.columnCount) == [1, 1])
    }

    @Test func emptyDayShowsTheWorkday() {
        let timeline = DayTimeline.make(inputs: [], workStart: 540, workEnd: 1080)
        #expect(timeline.blocks.isEmpty)
        #expect(timeline.rangeStart == 540)
        #expect(timeline.rangeEnd == 1080)
    }

    @Test func eventsOutsideTheWorkdayWidenTheRangeToWholeHours() {
        let timeline = DayTimeline.make(
            inputs: [input(1, "아침 운동", 7, 20), input(2, "주간 회의", 10), input(3, "팀 회식", 19, minutes: 180)],
            workStart: 540,
            workEnd: 1080
        )
        #expect(timeline.rangeStart == 7 * 60)
        #expect(timeline.rangeEnd == 22 * 60)
        #expect(timeline.workStart == 540)
        #expect(timeline.workEnd == 1080)
    }

    @Test func lateZeroLengthEventReachesMidnight() {
        let timeline = DayTimeline.make(inputs: [input(1, "약 먹기", 23, 30, minutes: 0)], workStart: 540, workEnd: 1080)
        #expect(timeline.blocks.first?.startMinute == 23 * 60 + 30)
        #expect(timeline.blocks.first?.endMinute == 1440)
        #expect(timeline.rangeEnd == 1440)
        #expect(timeline.hourMarks.last == 1440)
    }

    @Test func workdayOffTheHourRoundsTheRangeOutward() {
        let timeline = DayTimeline.make(inputs: [], workStart: 8 * 60 + 30, workEnd: 17 * 60 + 30)
        #expect(timeline.rangeStart == 8 * 60)
        #expect(timeline.rangeEnd == 18 * 60)
        #expect(timeline.workStart == 510)
        #expect(timeline.workEnd == 1050)
    }

    @Test func overlappingEventsShareColumns() {
        let timeline = DayTimeline.make(
            inputs: [
                input(3, "C", 10),
                input(4, "D", 13),
                input(1, "A", 9),
                input(2, "B", 9, 30),
            ],
            workStart: 540,
            workEnd: 1080
        )
        let blocks = Dictionary(uniqueKeysWithValues: timeline.blocks.map { ($0.id, $0) })
        #expect(timeline.blocks.map(\.id) == [uuid(1), uuid(2), uuid(3), uuid(4)])
        #expect(blocks[uuid(1)]?.column == 0)
        #expect(blocks[uuid(2)]?.column == 1)
        #expect(blocks[uuid(3)]?.column == 0)
        #expect([uuid(1), uuid(2), uuid(3)].map { blocks[$0]?.columnCount } == [2, 2, 2])
        #expect(blocks[uuid(4)]?.column == 0)
        #expect(blocks[uuid(4)]?.columnCount == 1)
    }

    @Test func sameStartPutsTheLongerOneFirst() {
        let timeline = DayTimeline.make(inputs: [input(1, "짧은 것", 10, minutes: 30), input(2, "긴 것", 10, minutes: 120)], workStart: 540, workEnd: 1080)
        #expect(timeline.blocks.map(\.id) == [uuid(2), uuid(1)])
        #expect(timeline.blocks.map(\.column) == [0, 1])
    }

    @Test func shortEventsAreDrawnAtLeastHalfAnHour() {
        let timeline = DayTimeline.make(inputs: [input(1, "알림", 10, minutes: 0), input(2, "통화", 10, 15, minutes: 10)], workStart: 540, workEnd: 1080)
        let blocks = Dictionary(uniqueKeysWithValues: timeline.blocks.map { ($0.id, $0) })
        #expect(blocks[uuid(1)]?.endMinute == 10 * 60 + 30)
        #expect(blocks[uuid(2)]?.endMinute == 10 * 60 + 45)
        #expect(blocks[uuid(1)]?.column == 0)
        #expect(blocks[uuid(2)]?.column == 1)
        #expect(blocks[uuid(2)]?.columnCount == 2)
    }

    @Test func orderDoesNotDependOnInput() {
        let inputs = [input(1, "A", 9), input(2, "B", 9, 30), input(3, "C", 10), input(4, "D", 13), input(5, "가", 13)]
        let expected = DayTimeline.make(inputs: inputs, workStart: 540, workEnd: 1080)
        #expect(DayTimeline.make(inputs: inputs.reversed(), workStart: 540, workEnd: 1080) == expected)
    }

    @Test func overnightEventIsSplitIntoEachDay() {
        let start = day(2026, 10, 19).date(hour: 22, in: seoul)
        let end = day(2026, 10, 20).date(hour: 2, in: seoul)
        let first = DayTimeline.Input(id: uuid(1), title: "야간 작업", start: start, end: end, on: day(2026, 10, 19), timeZone: seoul)
        #expect(first?.startMinute == 22 * 60)
        #expect(first?.endMinute == 1440)
        let second = DayTimeline.Input(id: uuid(1), title: "야간 작업", start: start, end: end, on: day(2026, 10, 20), timeZone: seoul)
        #expect(second?.startMinute == 0)
        #expect(second?.endMinute == 2 * 60)
        #expect(DayTimeline.Input(id: uuid(1), title: "야간 작업", start: start, end: end, on: day(2026, 10, 21), timeZone: seoul) == nil)
        #expect(DayTimeline.Input(id: uuid(1), title: "야간 작업", start: start, end: end, on: day(2026, 10, 18), timeZone: seoul) == nil)
    }

    @Test func endingAtMidnightStaysOnTheFirstDay() {
        let start = day(2026, 10, 19).date(hour: 22, in: seoul)
        let end = day(2026, 10, 20).date(in: seoul)
        let first = DayTimeline.Input(id: uuid(1), title: "영화", start: start, end: end, on: day(2026, 10, 19), timeZone: seoul)
        #expect(first?.startMinute == 22 * 60)
        #expect(first?.endMinute == 1440)
        #expect(DayTimeline.Input(id: uuid(1), title: "영화", start: start, end: end, on: day(2026, 10, 20), timeZone: seoul) == nil)
    }

    @Test func zeroLengthEventBelongsToItsOwnDay() {
        let midnight = day(2026, 10, 20).date(in: seoul)
        let input = DayTimeline.Input(id: uuid(1), title: "자정", start: midnight, end: midnight, on: day(2026, 10, 20), timeZone: seoul)
        #expect(input?.startMinute == 0)
        #expect(input?.endMinute == 0)
        #expect(DayTimeline.Input(id: uuid(1), title: "자정", start: midnight, end: midnight, on: day(2026, 10, 19), timeZone: seoul) == nil)
    }

    @Test func endBeforeStartIsTheStartAlone() {
        let start = day(2026, 10, 19).date(hour: 15, in: seoul)
        let input = DayTimeline.Input(id: uuid(1), title: "거꾸로", start: start, end: start.addingTimeInterval(-3600), on: day(2026, 10, 19), timeZone: seoul)
        #expect(input?.startMinute == 15 * 60)
        #expect(input?.endMinute == 15 * 60)
    }

    @Test func minuteAtPositionSnapsToHalfHours() {
        // 9–20시(11시간)
        let timeline = DayTimeline.make(inputs: [input(1, "저녁 약속", 19)], workStart: 540, workEnd: 1080)
        let height = 11 * 48.0
        #expect(timeline.minute(atY: 0, height: height) == 540)
        #expect(timeline.minute(atY: height * 6.75 / 11, height: height) == 15 * 60 + 30)
        #expect(timeline.minute(atY: height * 6.4 / 11, height: height) == 15 * 60)
        #expect(timeline.minute(atY: -20, height: height) == 540)
        #expect(timeline.minute(atY: height + 20, height: height) == 20 * 60 - 30)
        #expect(timeline.minute(atY: height, height: height) == 20 * 60 - 30)
        #expect(timeline.minute(atY: 10, height: 0) == 540)
    }

    @Test func positionOfMinute() {
        let timeline = DayTimeline.make(inputs: [], workStart: 540, workEnd: 1080)
        #expect(timeline.y(ofMinute: 540, height: 432) == 0)
        #expect(timeline.y(ofMinute: 600, height: 432) == 48)
        #expect(timeline.y(ofMinute: 1080, height: 432) == 432)
    }

    @Test func fixesInvalidWorkHours() {
        func fixed(_ start: Int, _ end: Int) -> [Int] {
            let hours = DayTimeline.normalizedWorkHours(start: start, end: end)
            return [hours.start, hours.end]
        }
        #expect(fixed(600, 600) == [600, 660])
        #expect(fixed(1000, 500) == [1000, 1060])
        #expect(fixed(-30, 2000) == [0, 1440])
        #expect(fixed(1440, 1440) == [1380, 1440])
        let timeline = DayTimeline.make(inputs: [], workStart: 1200, workEnd: 600)
        #expect(timeline.workStart == 1200)
        #expect(timeline.workEnd == 1260)
        #expect(timeline.rangeEnd == 1260)
    }
}
