import DayGridCore
import SwiftData
import SwiftUI

/// 날짜를 정하지 않은 할일과 일정("나중에" 목록).
///
/// - 위쪽 입력창에 적고 엔터를 치면 바로 할일로 들어가고, 입력창에 이어서 쓸 수 있다.
/// - 끌어서 순서를 바꾼다. 왼쪽으로 밀면 삭제·날짜, 오른쪽으로 밀면 완료가 나온다.
struct InboxTab: View {
    /// 값이 커지면 입력창에 포커스를 준다(홈 화면 퀵 액션).
    let focusRequest: Int

    @Environment(AppClock.self) private var clock
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: Item.inboxPredicate,
        sort: [SortDescriptor(\Item.inboxOrder), SortDescriptor(\Item.createdAt)]
    ) private var items: [Item]
    @Query(sort: \ItemCategory.sortOrder) private var categories: [ItemCategory]
    @State private var newTitle = ""
    @FocusState private var isInputFocused: Bool
    @State private var handledFocusRequest = 0
    @State private var assigningItem: Item?
    @State private var editorMode: ItemEditorView.Mode?

    init(focusRequest: Int = 0) {
        self.focusRequest = focusRequest
    }

    var body: some View {
        let pending = items.filter { !$0.isCompleted }
        let completed = items.filter(\.isCompleted)

        NavigationStack {
            List {
                Section {
                    TextField("할일을 적고 엔터", text: $newTitle)
                        .focused($isInputFocused)
                        .onSubmit(addTask)
                        .accessibilityIdentifier("inbox.input")
                }
                if items.isEmpty {
                    ContentUnavailableView(
                        "나중에 할일 없음",
                        systemImage: "tray",
                        description: Text("날짜를 정하지 않은 할일을 모아 두는 곳입니다.")
                    )
                    .listRowBackground(Color.clear)
                }
                if !pending.isEmpty {
                    Section {
                        ForEach(pending) { item in
                            row(item)
                        }
                        .onMove { source, destination in
                            move(pending, from: source, to: destination)
                        }
                    }
                }
                if !completed.isEmpty {
                    Section("완료") {
                        ForEach(completed) { item in
                            row(item)
                        }
                    }
                }
            }
            .accessibilityIdentifier("inbox.list")
            .navigationTitle("나중에")
            .toolbar {
                // 편집 중에 항목이 줄어도 편집을 끝낼 수 있도록, 목록이 비어 있지 않으면 늘 보인다.
                if !items.isEmpty {
                    EditButton()
                }
            }
            .sheet(item: $assigningItem) { item in
                AssignDateSheet(item: item, today: clock.today)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $editorMode) { mode in
                ItemEditorView(mode: mode)
            }
            .task(id: focusRequest) {
                guard focusRequest > handledFocusRequest else { return }
                handledFocusRequest = focusRequest
                // 탭이 바뀌는 중에는 포커스가 잡히지 않는다. 화면이 자리 잡을 때까지 잠깐 기다린다.
                try? await Task.sleep(for: .milliseconds(400))
                isInputFocused = true
            }
        }
    }

    private func row(_ item: Item) -> some View {
        InboxRowView(item: item)
            .contentShape(Rectangle())
            .onTapGesture {
                isInputFocused = false
                editorMode = .edit(item)
            }
            .swipeActions(edge: .trailing) {
                Button("삭제", role: .destructive) {
                    modelContext.delete(item)
                    try? modelContext.save()
                }
                Button("날짜") {
                    isInputFocused = false
                    assigningItem = item
                }
                .tint(.blue)
            }
            .swipeActions(edge: .leading) {
                if item.isTask {
                    Button(item.isCompleted ? "완료 취소" : "완료") {
                        item.toggleCompletion()
                        try? modelContext.save()
                    }
                    .tint(.green)
                }
            }
    }

    /// 입력창의 제목으로 할일을 만들어 맨 위에 넣고, 입력창에 이어서 쓸 수 있게 한다.
    /// 빈 채로 엔터를 치면 입력을 마친다(키보드가 내려간다).
    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let item = Item(title: title, isTask: true, category: categories.first)
        item.inboxOrder = Item.topInboxOrder(in: modelContext)
        modelContext.insert(item)
        try? modelContext.save()
        newTitle = ""
        // 엔터를 치면 입력창이 포커스를 잃는다. 이번 차례와 다음 차례에 다시 포커스를 줘서 이어서 쓸 수 있게 한다.
        isInputFocused = true
        Task { isInputFocused = true }
    }

    private func move(_ pending: [Item], from source: IndexSet, to destination: Int) {
        var ordered = pending
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, item) in ordered.enumerated() {
            item.inboxOrder = Double(index)
        }
        try? modelContext.save()
    }
}

private struct InboxRowView: View {
    let item: Item

    var body: some View {
        HStack(spacing: 12) {
            ItemMarker(item: item)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                if let category = item.category {
                    Text(category.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
