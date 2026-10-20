import DayGridCore
import SwiftData
import SwiftUI

/// 일정·할일 추가와 편집 시트.
struct ItemEditorView: View {
    enum Mode: Identifiable {
        case new(LocalDate)
        /// 달력에서 꾹 눌러 끈 기간의 새 종일 일정
        case newRange(LocalDate, LocalDate)
        case edit(Item)

        var id: String {
            switch self {
            case .new(let day): "new-\(day.iso8601)"
            case .newRange(let start, let end): "range-\(start.iso8601)-\(end.iso8601)"
            case .edit(let item): "edit-\(item.id.uuidString)"
            }
        }
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ItemCategory.sortOrder) private var categories: [ItemCategory]
    @State private var draft: ItemDraft
    @State private var isConfirmingDeletion = false

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .new(let day):
            _draft = State(initialValue: .new(on: day, categoryID: nil))
        case .newRange(let start, let end):
            _draft = State(initialValue: .newAllDay(from: start, through: end, categoryID: nil))
        case .edit(let item):
            _draft = State(initialValue: ItemDraft(item: item))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("제목", text: $draft.title)
                        .accessibilityIdentifier("editor.title")
                    Toggle("할일", isOn: $draft.isTask)
                }

                Section {
                    Toggle("날짜 지정", isOn: $draft.hasDate)
                    if draft.hasDate {
                        Toggle("종일", isOn: $draft.isAllDay)
                        DatePicker("시작", selection: startBinding, displayedComponents: dateComponents)
                        DatePicker("종료", selection: $draft.end, in: draft.earliestEnd()..., displayedComponents: dateComponents)
                    }
                } footer: {
                    if !draft.hasDate {
                        Text("날짜를 정하지 않으면 '나중에' 목록에 들어갑니다.")
                    }
                }

                if draft.hasDate {
                    Section("알림") {
                        ForEach(draft.isAllDay ? ReminderOption.allDayOptions : ReminderOption.timedOptions, id: \.self) { option in
                            Toggle(option.koreanText, isOn: reminderBinding(option))
                        }
                    }
                }

                Section {
                    Picker("카테고리", selection: $draft.categoryID) {
                        Text("없음").tag(UUID?.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                }

                Section("본문") {
                    NavigationLink {
                        BodyEditorView(text: $draft.note)
                    } label: {
                        bodyLabel
                    }
                    .accessibilityIdentifier("editor.body")
                }

                if let item = editingItem {
                    Section {
                        Button("복제해서 새 일정 만들기") {
                            saveCopy()
                        }
                        Button("삭제", role: .destructive) {
                            isConfirmingDeletion = true
                        }
                        .accessibilityIdentifier("editor.delete")
                        .confirmationDialog("이 일정을 삭제할까요?", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
                            Button("삭제", role: .destructive) {
                                delete(item)
                            }
                        }
                    }
                }
            }
            .navigationTitle(editingItem == nil ? "새 일정" : "일정 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(!draft.canSave)
                }
            }
            .onAppear {
                // 새 일정의 기본 카테고리는 목록의 첫 번째 카테고리.
                if editingItem == nil, draft.categoryID == nil {
                    draft.categoryID = categories.first?.id
                }
            }
        }
    }

    /// 본문이 있으면 첫 줄과 줄 수, 없으면 "본문 추가".
    @ViewBuilder
    private var bodyLabel: some View {
        if let summary = MarkdownSummary.firstLine(of: draft.note) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary)
                    .lineLimit(1)
                Text("\(draft.note.split(whereSeparator: \.isNewline).count)줄")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("본문 추가")
                .foregroundStyle(.secondary)
        }
    }

    private var editingItem: Item? {
        if case .edit(let item) = mode { return item }
        return nil
    }

    private var dateComponents: DatePickerComponents {
        draft.isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    /// 알림을 처음 켤 때 알림 권한을 묻는다.
    private func reminderBinding(_ option: ReminderOption) -> Binding<Bool> {
        Binding(
            get: { draft.reminderMask & option.bit != 0 },
            set: { isOn in
                if isOn {
                    draft.reminderMask |= option.bit
                    Task { await NotificationScheduler.shared.requestAuthorization() }
                } else {
                    draft.reminderMask &= ~option.bit
                }
            }
        )
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { draft.start },
            set: { draft.moveStart(to: $0) }
        )
    }

    private func save() {
        let topInboxOrder = Item.topInboxOrder(in: modelContext)
        let item: Item
        if let editingItem {
            item = editingItem
        } else {
            item = Item(title: draft.trimmedTitle)
            item.inboxOrder = topInboxOrder
            modelContext.insert(item)
        }
        draft.apply(to: item, categories: categories, inboxOrder: topInboxOrder)
        try? modelContext.save()
        dismiss()
    }

    private func saveCopy() {
        let copy = Item(title: draft.trimmedTitle)
        copy.inboxOrder = Item.topInboxOrder(in: modelContext)
        modelContext.insert(copy)
        draft.apply(to: copy, categories: categories)
        try? modelContext.save()
        dismiss()
    }

    private func delete(_ item: Item) {
        modelContext.delete(item)
        try? modelContext.save()
        dismiss()
    }
}
