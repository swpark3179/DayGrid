import DayGridCore
import SwiftData
import SwiftUI

/// 날짜를 누르면 열리는 하루 상세 시트. 종일·기간, 시간, 할일 순으로 보여준다.
/// 행을 왼쪽으로 밀면 삭제·복제, 오른쪽으로 밀면 "나중에"(날짜를 비우고 나중에 목록으로)가 나온다.
struct DayDetailView: View {
    let date: LocalDate

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HolidayService.self) private var holidayService
    @Query private var items: [Item]
    @Query private var personalHolidays: [PersonalHoliday]
    @Query(sort: \Person.name) private var people: [Person]
    @Query(
        filter: #Predicate<RecurringTask> { $0.isActive == true },
        sort: [SortDescriptor(\RecurringTask.sortOrder), SortDescriptor(\RecurringTask.createdAt)]
    ) private var recurringTasks: [RecurringTask]
    @Environment(AppClock.self) private var clock
    @State private var editorMode: ItemEditorView.Mode?

    init(date: LocalDate) {
        self.date = date
        _items = Query(filter: Item.predicate(overlapping: date...date), sort: \Item.startDayKey)
        _personalHolidays = Query(filter: PersonalHoliday.predicate(overlapping: date...date), sort: \PersonalHoliday.name)
    }

    var body: some View {
        let itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let agenda = DayAgenda.make(on: date, inputs: items.compactMap(\.agendaInput))

        NavigationStack {
            List {
                specialDaysSection
                if agenda.isEmpty {
                    ContentUnavailableView(
                        "일정 없음",
                        systemImage: "calendar",
                        description: Text("+ 버튼으로 이 날에 일정을 추가하세요.")
                    )
                    .listRowBackground(Color.clear)
                }
                section("종일 · 기간", rows: agenda.spanning, itemsByID: itemsByID)
                section("시간", rows: agenda.timed, itemsByID: itemsByID)
                section("할일", rows: agenda.tasks, itemsByID: itemsByID)
                recurringSection
            }
            .accessibilityIdentifier("dayDetail.list")
            .navigationTitle(date.koreanMonthDayWeekdayText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("일정 추가", systemImage: "plus") {
                        editorMode = .new(date)
                    }
                    .accessibilityIdentifier("dayDetail.add")
                }
            }
            .sheet(item: $editorMode) { mode in
                ItemEditorView(mode: mode)
            }
        }
    }

    /// 이 날이 속한 주기가 있는 반복 할일. 그 주기가 지금 주기면 체크할 수 있다.
    @ViewBuilder
    private var recurringSection: some View {
        let tasks = recurringTasks.filter { $0.cycleStatus(on: date, today: clock.today) != nil }
        if !tasks.isEmpty {
            Section("반복 할일") {
                ForEach(tasks) { task in
                    RecurringTaskRow(task: task, date: date, today: clock.today)
                }
            }
        }
    }

    /// 공휴일, 개인 휴일, 생일. 하나도 없으면 섹션을 그리지 않는다.
    @ViewBuilder
    private var specialDaysSection: some View {
        let holidays = holidayService.holidays(in: date...date)
        let birthdayPeople = people.filter { !$0.birthday.occurrences(in: date...date).isEmpty }
        if !holidays.isEmpty || !personalHolidays.isEmpty || !birthdayPeople.isEmpty {
            Section("기념일") {
                ForEach(holidays, id: \.self) { holiday in
                    SpecialDayRow(title: holiday.name, detail: "공휴일", systemImage: "flag.fill", isHoliday: true)
                }
                ForEach(personalHolidays) { holiday in
                    SpecialDayRow(title: holiday.name, detail: "개인 휴일", systemImage: "sun.max.fill", isHoliday: true)
                }
                ForEach(birthdayPeople) { person in
                    let detail = [person.birthday.koreanText, person.ordinalText(on: date)].compactMap { $0 }.joined(separator: " · ")
                    SpecialDayRow(title: "\(person.name) 생일", detail: detail, systemImage: "gift.fill", isHoliday: false)
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, rows: [DayAgenda.Row], itemsByID: [UUID: Item]) -> some View {
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows) { row in
                    if let item = itemsByID[row.id] {
                        AgendaRowView(item: item, row: row)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editorMode = .edit(item)
                            }
                            .swipeActions {
                                Button("삭제", role: .destructive) {
                                    modelContext.delete(item)
                                    try? modelContext.save()
                                }
                                Button("복제") {
                                    modelContext.insert(item.duplicate())
                                    try? modelContext.save()
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .leading) {
                                Button("나중에") {
                                    item.moveToInbox(order: Item.topInboxOrder(in: modelContext))
                                    try? modelContext.save()
                                }
                                .tint(.orange)
                            }
                    }
                }
            }
        }
    }
}

private struct SpecialDayRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let isHoliday: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(isHoliday ? Color.red : Color.pink)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(isHoliday ? Color.red : Color.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AgendaRowView: View {
    let item: Item
    let row: DayAgenda.Row

    var body: some View {
        HStack(spacing: 12) {
            ItemMarker(item: item)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                Text(ItemTimeText.describe(item, row: row))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                BodySummaryLine(item: item)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

extension Item {
    /// 하루 상세 목록에 넣을 값. 날짜가 없으면 `nil`.
    var agendaInput: DayAgenda.Input? {
        guard let entry = calendarEntry() else { return nil }
        return DayAgenda.Input(entry: entry, title: title, isTask: isTask, isCompleted: isCompleted)
    }
}
