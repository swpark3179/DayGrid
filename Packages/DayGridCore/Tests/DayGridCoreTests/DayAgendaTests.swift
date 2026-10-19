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

private func allDay(_ id: Int, _ title: String, _ start: LocalDate, _ end: LocalDate? = nil, task: Bool = false, done: Bool = false) -> DayAgenda.Input {
    DayAgenda.Input(entry: .allDay(id: uuid(id), from: start, through: end ?? start), title: title, isTask: task, isCompleted: done)
}

private func timed(_ id: Int, _ title: String, _ date: LocalDate, minute: Int, endDay: LocalDate? = nil, task: Bool = false, done: Bool = false) -> DayAgenda.Input {
    let entry = CalendarEntry(id: uuid(id), startDay: date, endDay: endDay ?? date, isAllDay: false, startMinute: minute)
    return DayAgenda.Input(entry: entry, title: title, isTask: task, isCompleted: done)
}

@Suite("DayAgenda")
struct DayAgendaTests {
    private let date = day(2026, 10, 30)

    private var inputs: [DayAgenda.Input] {
        [
            timed(5, "저녁 약속", date, minute: 19 * 60),
            allDay(2, "보고서 제출", date),
            timed(8, "메일 정리", date, minute: 10 * 60, task: true),
            timed(3, "세미나", date, minute: 9 * 60),
            timed(10, "야간 작업", day(2026, 10, 29), minute: 23 * 60, endDay: date),
            timed(6, "운동", date, minute: 8 * 60, task: true, done: true),
            allDay(1, "출장", day(2026, 10, 28), day(2026, 11, 3)),
            allDay(7, "장보기", date, task: true),
            timed(4, "병원", date, minute: 15 * 60),
            allDay(9, "다음 날 일정", day(2026, 10, 31)),
        ]
    }

    @Test func groupsAndOrdersTheDay() {
        let agenda = DayAgenda.make(on: date, inputs: inputs)
        #expect(agenda.date == date)
        #expect(agenda.spanning.map(\.id) == [uuid(1), uuid(10), uuid(2)])
        #expect(agenda.timed.map(\.id) == [uuid(3), uuid(4), uuid(5)])
        #expect(agenda.tasks.map(\.id) == [uuid(7), uuid(8), uuid(6)])
        #expect(!agenda.isEmpty)
    }

    @Test func orderDoesNotDependOnInput() {
        let expected = DayAgenda.make(on: date, inputs: inputs)
        #expect(DayAgenda.make(on: date, inputs: inputs.reversed()) == expected)
    }

    @Test func multiDayRowsKnowWhichDayItIs() {
        let agenda = DayAgenda.make(on: date, inputs: inputs)
        let trip = agenda.spanning.first { $0.id == uuid(1) }
        #expect(trip?.dayNumber == 3)
        #expect(trip?.totalDays == 7)
        let overnight = agenda.spanning.first { $0.id == uuid(10) }
        #expect(overnight?.dayNumber == 2)
        #expect(overnight?.totalDays == 2)
        let report = agenda.spanning.first { $0.id == uuid(2) }
        #expect(report?.dayNumber == 1)
        #expect(report?.totalDays == 1)
    }

    @Test func sameStartAndLengthFallsBackToTitle() {
        let agenda = DayAgenda.make(on: date, inputs: [allDay(2, "나", date), allDay(1, "가", date), allDay(3, "가", date)])
        #expect(agenda.spanning.map(\.id) == [uuid(1), uuid(3), uuid(2)])
    }

    @Test func emptyDay() {
        let agenda = DayAgenda.make(on: day(2026, 10, 21), inputs: inputs)
        #expect(agenda.isEmpty)
    }
}
