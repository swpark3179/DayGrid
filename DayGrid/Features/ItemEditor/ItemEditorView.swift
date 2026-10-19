import DayGridCore
import SwiftData
import SwiftUI

/// 일정·할일 추가와 편집 시트.
struct ItemEditorView: View {
    enum Mode: Identifiable {
        case new(LocalDate)
        case edit(Item)

        var id: String {
            switch self {
            case .new(let day): "new-\(day.iso8601)"
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
                    Toggle("종일", isOn: $draft.isAllDay)
                    DatePicker("시작", selection: startBinding, displayedComponents: dateComponents)
                    DatePicker("종료", selection: $draft.end, in: draft.earliestEnd()..., displayedComponents: dateComponents)
                }

                Section {
                    Picker("카테고리", selection: $draft.categoryID) {
                        Text("없음").tag(UUID?.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                }

                Section("메모") {
                    TextField("메모", text: $draft.note, axis: .vertical)
                        .lineLimit(3...8)
                }

                if let item = editingItem {
                    Section {
                        Button("복제해서 새 일정 만들기") {
                            saveCopy()
                        }
                        Button("삭제", role: .destructive) {
                            isConfirmingDeletion = true
                        }
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

    private var editingItem: Item? {
        if case .edit(let item) = mode { return item }
        return nil
    }

    private var dateComponents: DatePickerComponents {
        draft.isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { draft.start },
            set: { draft.moveStart(to: $0) }
        )
    }

    private func save() {
        let item: Item
        if let editingItem {
            item = editingItem
        } else {
            item = Item(title: draft.trimmedTitle)
            modelContext.insert(item)
        }
        draft.apply(to: item, categories: categories)
        try? modelContext.save()
        dismiss()
    }

    private func saveCopy() {
        let copy = Item(title: draft.trimmedTitle)
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
