import DayGridCore
import SwiftData
import SwiftUI

/// 일정·할일 추가와 편집 시트. 제목 → 날짜와 시간 → 카테고리 → 본문 → 알림 순이다.
///
/// - 달력의 일정은 늘 날짜가 있으므로 "날짜 지정" 토글을 두지 않는다(사용자 요청 2026-10-22).
///   대신 삭제 위의 "나중에 할일로 미루기"가 고친 내용을 저장하며 "나중에" 목록으로 보내고, "나중에" 탭을 연다.
///   날짜 토글은 "나중에" 항목을 고칠 때만 보인다(날짜를 정해 달력에 넣는 길).
/// - "시간 지정"을 켜면 시각까지, 끄면 날짜만 고른다(종일).
/// - 알림은 칩(`ReminderChips`)으로 여러 개를 켜고 끈다.
struct ItemEditorView: View {
    enum Mode: Identifiable {
        case new(LocalDate)
        /// 시간을 정하지 않은 새 일정. 달력에서 꾹 눌러 끈 기간, 하루 상세의 + 버튼(그 날 하루)이 연다.
        case newRange(LocalDate, LocalDate)
        /// 하루 상세 타임라인의 빈 곳을 눌러 그 시각(자정부터 지난 분)부터 여는 새 일정
        case newTimed(LocalDate, minute: Int)
        case edit(Item)

        var id: String {
            switch self {
            case .new(let day): "new-\(day.iso8601)"
            case .newRange(let start, let end): "range-\(start.iso8601)-\(end.iso8601)"
            case .newTimed(let day, let minute): "timed-\(day.iso8601)-\(minute)"
            case .edit(let item): "edit-\(item.id.uuidString)"
            }
        }
    }

    let mode: Mode
    /// "나중에 할일로 미루기"로 저장한 뒤 부른다. 부르는 쪽이 시트를 닫고 "나중에" 탭을 연다. 없으면 이 시트만 닫는다.
    var onMovedToInbox: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ItemCategory.sortOrder) private var categories: [ItemCategory]
    @State private var draft: ItemDraft
    @State private var isConfirmingDeletion = false
    /// 열 때 "나중에" 목록에 있던 항목인지. 날짜 토글과 미루기 버튼을 정한다.
    /// 모델을 보지 않고 처음 값을 두는 것은, 미룬 뒤 시트가 닫히는 동안 화면이 바뀌지 않게 하려는 것이다.
    @State private var isInboxItem: Bool

    init(mode: Mode, onMovedToInbox: (() -> Void)? = nil) {
        self.mode = mode
        self.onMovedToInbox = onMovedToInbox
        if case .edit(let item) = mode {
            _isInboxItem = State(initialValue: !item.isScheduled)
        } else {
            _isInboxItem = State(initialValue: false)
        }
        switch mode {
        case .new(let day):
            _draft = State(initialValue: .new(on: day, categoryID: nil))
        case .newRange(let start, let end):
            _draft = State(initialValue: .newAllDay(from: start, through: end, categoryID: nil))
        case .newTimed(let day, let minute):
            _draft = State(initialValue: .new(on: day, startMinute: minute, categoryID: nil))
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
                    // 켜고 끌 때 아래 줄이 열리고 닫히도록 바인딩에 애니메이션을 단다.
                    if isInboxItem {
                        Toggle("날짜 지정", isOn: $draft.hasDate.animation(.snappy))
                    }
                    if draft.hasDate {
                        Toggle("시간 지정", isOn: $draft.hasTime.animation(.snappy))
                        DatePicker("시작", selection: startBinding, displayedComponents: dateComponents)
                        DatePicker("종료", selection: $draft.end, in: draft.earliestEnd()..., displayedComponents: dateComponents)
                    }
                } footer: {
                    if !draft.hasDate {
                        Text("날짜를 정하지 않으면 '나중에' 목록에 들어갑니다.")
                    }
                }

                Section("카테고리") {
                    CategoryChips(categories: categories, selection: $draft.categoryID)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section("본문") {
                    NavigationLink {
                        BodyEditorView(text: $draft.note)
                    } label: {
                        bodyLabel
                    }
                    .accessibilityIdentifier("editor.body")
                }

                if draft.hasDate {
                    Section("알림") {
                        ReminderChips(
                            options: draft.hasTime ? ReminderOption.timedOptions : ReminderOption.allDayOptions,
                            mask: reminderMaskBinding
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                if let item = editingItem {
                    Section {
                        Button("복제해서 새 일정 만들기") {
                            saveCopy()
                        }
                        if !isInboxItem {
                            Button("나중에 할일로 미루기") {
                                moveToInbox(item)
                            }
                            .disabled(!draft.canSave)
                            .accessibilityIdentifier("editor.moveToInbox")
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

    /// 알림을 켤 때 알림 권한을 묻는다.
    private var reminderMaskBinding: Binding<Int> {
        Binding(
            get: { draft.reminderMask },
            set: { mask in
                let turnedOn = mask & ~draft.reminderMask != 0
                draft.reminderMask = mask
                if turnedOn {
                    Task { await NotificationScheduler.shared.requestAuthorization() }
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

    /// 고친 내용을 저장하면서 날짜를 비워 "나중에" 목록 맨 위로 보낸다. 지금 모양(종일 일수, 시각과 길이)은 힌트로 남는다.
    private func moveToInbox(_ item: Item) {
        var deferred = draft
        deferred.hasDate = false
        deferred.apply(to: item, categories: categories, inboxOrder: Item.topInboxOrder(in: modelContext))
        try? modelContext.save()
        if let onMovedToInbox {
            onMovedToInbox()
        } else {
            dismiss()
        }
    }

    private func delete(_ item: Item) {
        modelContext.delete(item)
        try? modelContext.save()
        dismiss()
    }
}
