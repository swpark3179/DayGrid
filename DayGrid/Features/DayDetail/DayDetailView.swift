import DayGridCore
import SwiftData
import SwiftUI
import UIKit

/// 날짜를 누르면 열리는 하루 상세 시트. 종일·기간, 시간, 할일 순으로 보여준다.
/// 행을 왼쪽으로 밀면 삭제·복제, 오른쪽으로 밀면 "나중에"(날짜를 비우고 나중에 목록으로)가 나온다.
///
/// 행을 꾹 누르면 옮기기가 된다(사용자 요청 2026-10-21). 시트가 아래로 작아져 달력이 보이고,
/// 손가락을 떼지 않고 다른 날짜 위에서 놓으면 그만큼 날짜를 옮긴다(`Item.move(byDays:)`, 시각과 길이는 그대로).
/// 달력 밖이나 같은 날에 놓으면 그대로 두고 시트를 되돌린다.
///
/// 설정의 보기 방식이 타임라인이면, 시간이 있는 일정과 할일은 업무 시간 타임라인(`DayTimelineView`)에 놓고
/// 종일·기간과 시간 없는 할일은 그 아래에 목록으로 보여준다. 타임라인 블록은 꾹 눌러 같은 동작을 고른다.
struct DayDetailView: View {
    let date: LocalDate

    /// 옮기는 동안의 시트 높이. 달력을 가리지 않게 작게 둔다.
    static let movingDetent = PresentationDetent.height(64)

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HolidayService.self) private var holidayService
    @Query private var items: [Item]
    @Query private var personalHolidays: [PersonalHoliday]
    @Query(sort: \Person.name) private var people: [Person]
    @Query(filter: RecurringTask.activePredicate, sort: \RecurringTask.sortOrder) private var recurringTasks: [RecurringTask]
    @Environment(AppClock.self) private var clock
    @State private var editorMode: ItemEditorView.Mode?
    @State private var readingItem: ReaderSelection?
    @AppStorage(AppSettings.dayDetailStyleKey) private var style = DayDetailStyle.list
    @AppStorage(AppSettings.workdayStartMinuteKey) private var workdayStart = AppSettings.defaultWorkdayStartMinute
    @AppStorage(AppSettings.workdayEndMinuteKey) private var workdayEnd = AppSettings.defaultWorkdayEndMinute
    @State private var detent = PresentationDetent.medium
    @State private var detentBeforeMove = PresentationDetent.medium
    @State private var movingItemID: UUID?
    @State private var moveSession = ItemMoveSession()
    @State private var contentHeight: CGFloat = 0
    /// 옮기는 동안 고정하는 목록 높이. 시트가 작아져도 목록은 그대로 두어 셀이 재사용되지 않게 한다
    /// (꾹 누른 행의 셀이 빠지면 손가락 추적이 끊긴다).
    @State private var frozenHeight: CGFloat?

    init(date: LocalDate) {
        self.date = date
        _items = Query(filter: Item.predicate(overlapping: date...date), sort: \Item.startDayKey)
        _personalHolidays = Query(filter: PersonalHoliday.predicate(overlapping: date...date), sort: \PersonalHoliday.name)
    }

    var body: some View {
        let itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let isTimeline = style == .timeline
        let agenda = DayAgenda.make(on: date, inputs: items.compactMap(\.agendaInput), separatingTimed: isTimeline)

        NavigationStack {
            List {
                specialDaysSection
                if isTimeline {
                    timelineSection(rows: agenda.timed, itemsByID: itemsByID)
                } else if agenda.isEmpty {
                    ContentUnavailableView(
                        "일정 없음",
                        systemImage: "calendar",
                        description: Text("+ 버튼으로 이 날에 일정을 추가하세요.")
                    )
                    .listRowBackground(Color.clear)
                }
                section("종일 · 기간", rows: agenda.spanning, itemsByID: itemsByID)
                if !isTimeline {
                    section("시간", rows: agenda.timed, itemsByID: itemsByID)
                }
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
            .sheet(item: $readingItem) { selection in
                ItemReaderView(item: selection.item, timeText: selection.timeText)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .frame(height: frozenHeight)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            if movingItemID != nil {
                MoveHintBar()
            }
        }
        .presentationDetents(detents, selection: $detent)
        .presentationBackgroundInteraction(movingItemID == nil ? .automatic : .enabled)
        .interactiveDismissDisabled(movingItemID != nil)
        .onDisappear {
            moveSession.end()
        }
    }

    /// 타임라인 보기. 시간이 있는 일정과 할일을 업무 시간 격자에 놓는다. 비어 있어도 격자를 그린다.
    private func timelineSection(rows: [DayAgenda.Row], itemsByID: [UUID: Item]) -> some View {
        let timeline = DayTimeline.make(
            inputs: rows.compactMap { itemsByID[$0.id]?.timelineInput(on: date) },
            workStart: workdayStart,
            workEnd: workdayEnd
        )
        return Section("타임라인") {
            DayTimelineView(
                date: date,
                timeline: timeline,
                itemsByID: itemsByID,
                rowsByID: Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
                onEdit: { editorMode = .edit($0) },
                onShowBody: { item, timeText in
                    readingItem = ReaderSelection(item: item, timeText: timeText)
                },
                onCreate: { editorMode = .newTimed(date, minute: $0) }
            ) { item in
                Button("복제", systemImage: "plus.square.on.square") { duplicate(item) }
                Button("나중에", systemImage: "tray") { moveToInbox(item) }
                Button("삭제", systemImage: "trash", role: .destructive) { delete(item) }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
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
                    SpecialDayRow(title: holiday.name, detail: "공휴일", systemImage: "flag.fill", kind: .publicHoliday)
                }
                ForEach(personalHolidays) { holiday in
                    SpecialDayRow(title: holiday.name, detail: "개인 휴일", systemImage: "sun.max.fill", kind: .personalHoliday)
                }
                ForEach(birthdayPeople) { person in
                    let detail = [person.birthday.koreanText, person.ordinalText(on: date)].compactMap { $0 }.joined(separator: " · ")
                    SpecialDayRow(title: "\(person.name) 생일", detail: detail, systemImage: "gift.fill", kind: .birthday)
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
                        AgendaRowView(item: item, row: row) { timeText in
                            readingItem = ReaderSelection(item: item, timeText: timeText)
                        }
                            .contentShape(Rectangle())
                            .gesture(WindowPressGesture { phase, point, window in
                                handlePress(phase, at: point, in: window, on: item)
                            })
                            .swipeActions {
                                Button("삭제", role: .destructive) {
                                    delete(item)
                                }
                                Button("복제") {
                                    duplicate(item)
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .leading) {
                                Button("나중에") {
                                    moveToInbox(item)
                                }
                                .tint(.orange)
                            }
                    }
                }
            }
        }
    }

    /// 시트 높이. 옮기는 동안은 작은 높이 하나만 두어 시트가 끌려 커지지 않게 한다.
    private var detents: Set<PresentationDetent> {
        movingItemID == nil ? [.medium, .large] : [Self.movingDetent]
    }

    /// 행 누르기: 짧게 누르면 편집, 꾹 누르면 다른 날로 옮기기.
    private func handlePress(_ phase: RangePressGesture.Phase, at point: CGPoint, in window: UIWindow?, on item: Item) {
        switch phase {
        case .tap:
            editorMode = .edit(item)
        case .began:
            guard movingItemID == nil, let window else { return }
            frozenHeight = contentHeight > 0 ? contentHeight : nil
            detentBeforeMove = detent
            movingItemID = item.id
            detent = Self.movingDetent
            moveSession.begin(
                title: item.title,
                colorHex: item.category?.colorHex ?? CategoryPalette.uncategorizedHex,
                from: date,
                at: point,
                in: window
            )
        case .changed:
            moveSession.update(to: point)
        case .ended:
            guard movingItemID == item.id else { return }
            if let target = moveSession.finish(at: point) {
                item.move(byDays: date.days(until: target))
                try? modelContext.save()
                // 시트는 작은 채로 닫는다. 달력에 옮긴 결과가 바로 보인다.
                dismiss()
            } else {
                endMove()
            }
        case .cancelled:
            moveSession.end()
            endMove()
        }
    }

    /// 옮기기를 그만두고 시트를 원래 높이로 되돌린다.
    private func endMove() {
        movingItemID = nil
        detent = detentBeforeMove
        frozenHeight = nil
    }

    private func delete(_ item: Item) {
        modelContext.delete(item)
        try? modelContext.save()
    }

    private func duplicate(_ item: Item) {
        modelContext.insert(item.duplicate())
        try? modelContext.save()
    }

    /// 날짜를 비우고 "나중에" 목록 맨 위로 보낸다. 직전 일정의 모양은 힌트로 남는다.
    private func moveToInbox(_ item: Item) {
        item.moveToInbox(order: Item.topInboxOrder(in: modelContext))
        try? modelContext.save()
    }
}

private struct SpecialDayRow: View {
    enum Kind {
        case publicHoliday
        case personalHoliday
        case birthday
    }

    let title: String
    let detail: String
    let systemImage: String
    let kind: Kind

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(titleColor)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var iconColor: Color {
        switch kind {
        case .publicHoliday: DayStyle.publicHolidayColor
        case .personalHoliday: DayStyle.personalHolidayColor
        case .birthday: .pink
        }
    }

    private var titleColor: Color {
        switch kind {
        case .publicHoliday: DayStyle.publicHolidayColor
        case .personalHoliday: DayStyle.personalHolidayColor
        case .birthday: .primary
        }
    }
}

/// 하루 상세의 일정 한 줄. 본문이 있으면 오른쪽 버튼으로 읽기 화면을 연다(행을 누르면 편집).
private struct AgendaRowView: View {
    let item: Item
    let row: DayAgenda.Row
    let onShowBody: (String) -> Void

    var body: some View {
        let timeText = ItemTimeText.describe(item, row: row)
        HStack(spacing: 12) {
            ItemMarker(item: item)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if item.bodySummary != nil {
                Button("본문 보기", systemImage: "doc.text") {
                    onShowBody(timeText)
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("dayDetail.body")
            }
        }
        .padding(.vertical, 2)
    }
}

/// 옮기는 동안 작아진 시트 위쪽에 보이는 안내. 시트의 제목 줄을 덮는다.
private struct MoveHintBar: View {
    var body: some View {
        Label("옮길 날짜 위에서 놓으세요. 여기에 놓으면 취소합니다.", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(.bar)
            .allowsHitTesting(false)
    }
}

/// 읽기 화면을 띄우기 위한 선택값. 시간 문구는 하루 상세에서 그 날 기준으로 만든 것을 넘긴다.
private struct ReaderSelection: Identifiable {
    let item: Item
    let timeText: String

    var id: UUID { item.id }
}

extension Item {
    /// 하루 상세 목록에 넣을 값. 날짜가 없으면 `nil`.
    var agendaInput: DayAgenda.Input? {
        guard let entry = calendarEntry() else { return nil }
        return DayAgenda.Input(entry: entry, title: title, isTask: isTask, isCompleted: isCompleted)
    }

    /// 하루 상세 타임라인에 넣을 값. 종일이거나 날짜가 없거나 `date`에 걸치지 않으면 `nil`.
    func timelineInput(on date: LocalDate, timeZone: TimeZone = .current) -> DayTimeline.Input? {
        guard !isAllDay, isScheduled, let startDate else { return nil }
        return DayTimeline.Input(id: id, title: title, start: startDate, end: endDate ?? startDate, on: date, timeZone: timeZone)
    }
}
