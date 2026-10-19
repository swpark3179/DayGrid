import DayGridCore
import Foundation
import SwiftData
import Testing
@testable import DayGrid

@MainActor
struct BirthdayAndHolidayModelTests {
    let container: ModelContainer

    var context: ModelContext { container.mainContext }

    init() throws {
        let schema = AppModelContainer.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [configuration])
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: year, month: month, day: day)!
    }

    // MARK: - 생일

    @Test func birthdayIsStoredInSeparateFields() {
        let person = Person(name: "엄마", birthday: Birthday(month: 10, day: 22))
        #expect(person.birthMonth == 10)
        #expect(person.birthDay == 22)
        #expect(!person.isLunar)

        person.birthday = Birthday(month: 4, day: 3, isLunar: true, isLeapMonth: true)
        #expect(person.birthMonth == 4)
        #expect(person.birthDay == 3)
        #expect(person.isLunar)
        #expect(person.isLeapMonth)
        #expect(person.birthday == Birthday(month: 4, day: 3, isLunar: true, isLeapMonth: true))
    }

    @Test func ordinalTextNeedsASolarBirthYear() {
        let minsu = Person(name: "김민수", birthday: Birthday(month: 10, day: 22), birthYear: 1990)
        #expect(minsu.ordinalText(on: day(2026, 10, 22)) == "36번째 생일")
        #expect(minsu.ordinalText(on: day(1990, 10, 22)) == nil)

        let unknownYear = Person(name: "아빠", birthday: Birthday(month: 11, day: 8))
        #expect(unknownYear.ordinalText(on: day(2026, 11, 8)) == nil)

        let lunar = Person(name: "엄마", birthday: Birthday(month: 9, day: 17, isLunar: true), birthYear: 1960)
        #expect(lunar.ordinalText(on: day(2026, 10, 27)) == nil)
    }

    // MARK: - 개인 휴일

    @Test func personalHolidayEndNeverPrecedesItsStart() {
        let holiday = PersonalHoliday(name: "휴가", from: day(2026, 10, 20), through: day(2026, 10, 18))
        #expect(holiday.startDayKey == 20_261_020)
        #expect(holiday.endDayKey == 20_261_020)

        holiday.setDays(from: day(2026, 10, 21), through: day(2026, 10, 23))
        #expect(holiday.startDay == day(2026, 10, 21))
        #expect(holiday.endDay == day(2026, 10, 23))

        holiday.setDays(from: day(2026, 10, 25), through: day(2026, 10, 24))
        #expect(holiday.endDay == day(2026, 10, 25))
    }

    @Test func predicateFindsHolidaysOverlappingTheRange() throws {
        context.insert(PersonalHoliday(name: "9월 말부터", from: day(2026, 9, 28), through: day(2026, 10, 2)))
        context.insert(PersonalHoliday(name: "창립기념일", from: day(2026, 10, 16), through: day(2026, 10, 16)))
        context.insert(PersonalHoliday(name: "11월", from: day(2026, 11, 1), through: day(2026, 11, 3)))
        context.insert(PersonalHoliday(name: "9월", from: day(2026, 9, 1), through: day(2026, 9, 30)))
        let empty = PersonalHoliday(name: "날짜 없음", from: day(2026, 10, 10), through: day(2026, 10, 10))
        empty.startDayKey = 0
        context.insert(empty)
        try context.save()

        let october = day(2026, 10, 1)...day(2026, 10, 31)
        let found = try context.fetch(FetchDescriptor<PersonalHoliday>(predicate: PersonalHoliday.predicate(overlapping: october)))
        #expect(Set(found.map(\.name)) == ["9월 말부터", "창립기념일"])
    }

    @Test func markFallsBackToTheStartDay() throws {
        let holiday = PersonalHoliday(name: "휴가", from: day(2026, 10, 21), through: day(2026, 10, 23))
        let mark = try #require(holiday.mark)
        #expect(mark.name == "휴가")
        #expect(mark.start == day(2026, 10, 21))
        #expect(mark.end == day(2026, 10, 23))

        holiday.endDayKey = 0
        #expect(holiday.mark?.end == day(2026, 10, 21))

        holiday.startDayKey = 0
        #expect(holiday.mark?.name == nil)
    }
}
