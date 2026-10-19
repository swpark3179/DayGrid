import DayGridCore
import SwiftData
import SwiftUI

/// 날짜를 누르면 열리는 하루 상세 시트. 종일·기간, 시간, 할일 순으로 보여준다.
/// 행을 왼쪽으로 밀면 삭제·복제, 오른쪽으로 밀면 "나중에"(날짜를 비우고 나중에 목록으로)가 나온다.
struct DayDetailView: View {
    let date: LocalDate

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @State private var editorMode: ItemEditorView.Mode?

    init(date: LocalDate) {
        self.date = date
        _items = Query(filter: Item.predicate(overlapping: date...date), sort: \Item.startDayKey)
    }

    var body: some View {
        let itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let agenda = DayAgenda.make(on: date, inputs: items.compactMap(\.agendaInput))

        NavigationStack {
            List {
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
