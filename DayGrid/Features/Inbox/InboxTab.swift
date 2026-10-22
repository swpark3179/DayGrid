import DayGridCore
import SwiftData
import SwiftUI
import TipKit
import UIKit

/// 날짜를 정하지 않은 할일과 일정("나중에" 목록).
///
/// - 위쪽 입력창에 적고 엔터를 치면 바로 할일로 들어가고, 입력창에 이어서 쓸 수 있다. 입력창 밖을 누르면 키보드가 내려간다.
/// - 편집에서 끌어서 순서를 바꾼다. 왼쪽으로 밀면 삭제·날짜, 오른쪽으로 밀면 완료가 나온다.
/// - 항목을 꾹 누르면 목록 위에 달력이 덮인다(`InboxCalendarOverlay`). 손을 떼지 않고 날짜 위에서 떼면 그 날로 들어가고,
///   달력 탭에서 그 달이 열린다. 달력 밖에서 떼거나 거의 움직이지 않고 떼면 그대로 둔다.
///   행의 탭(편집)과 꾹 누르기는 하루 상세와 같은 `WindowPressGesture` 하나가 받는다.
/// - 새 행이 들어오고 완료한 행이 "완료"로 옮겨 가는 것은 `@Query`의 애니메이션으로 움직인다.
///   밀어서 지우면 아래쪽에 잠깐 "실행 취소" 토스트가 뜬다(`UndoToastState`).
struct InboxTab: View {
    /// 값이 커지면 입력창에 포커스를 준다(홈 화면 퀵 액션).
    let focusRequest: Int
    /// 달력에 넣은 뒤 부른다. RootView가 달력 탭에서 그 날의 달을 연다.
    var onScheduled: (LocalDate) -> Void = { _ in }

    @Environment(AppClock.self) private var clock
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: Item.inboxPredicate,
        sort: [SortDescriptor(\Item.inboxOrder), SortDescriptor(\Item.createdAt)],
        animation: .snappy
    ) private var items: [Item]
    @Query(sort: \ItemCategory.sortOrder) private var categories: [ItemCategory]
    @State private var newTitle = ""
    @FocusState private var isInputFocused: Bool
    @State private var handledFocusRequest = 0
    @State private var assigningItem: Item?
    @State private var editorMode: ItemEditorView.Mode?
    /// 순서를 바꾸는 편집 중에는 달력으로 끌지 않는다.
    @State private var editMode: EditMode = .inactive
    /// 꾹 눌러 달력에 넣는 중인 항목
    @State private var movingItemID: UUID?
    @State private var moveSession = ItemMoveSession()
    /// 덮개 달력이 보여주는 달(`monthIndex`)
    @State private var overlayMonth = 0
    @State private var toast = UndoToastState()
    /// 빠른 입력으로 넣은 수. 늘 때마다 입력창에 잠깐 "넣음"이 보이고 가벼운 햅틱이 온다.
    @State private var addedCount = 0
    @State private var isShowingAdded = false
    /// 달력에 넣기 팁을 보일지(`InboxDropTip.shouldDisplayUpdates`). 숨긴 팁이 빈 행으로 남지 않게 따로 둔다.
    @State private var showsDropTip = false

    init(focusRequest: Int = 0, onScheduled: @escaping (LocalDate) -> Void = { _ in }) {
        self.focusRequest = focusRequest
        self.onScheduled = onScheduled
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
                        .overlay(alignment: .trailing) {
                            if isShowingAdded {
                                Label("넣음", systemImage: "checkmark")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.green)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                            }
                        }
                }
                if showsDropTip, !pending.isEmpty {
                    TipView(InboxDropTip())
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
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
                        .onMove(perform: reorderAction(for: pending))
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
            .background(KeyboardDismissOnTap(isActive: isInputFocused) { isInputFocused = false })
            .navigationTitle("나중에")
            .toolbar {
                // 편집 중에 항목이 줄어도 편집을 끝낼 수 있도록, 목록이 비어 있지 않으면 늘 보인다.
                if !items.isEmpty {
                    EditButton()
                }
            }
            .environment(\.editMode, $editMode)
            .undoToast(toast, hidden: movingItemID != nil)
            .task {
                for await shouldDisplay in InboxDropTip().shouldDisplayUpdates {
                    showsDropTip = shouldDisplay
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: addedCount)
            .task(id: addedCount) {
                guard addedCount > 0 else { return }
                withAnimation(.snappy) { isShowingAdded = true }
                try? await Task.sleep(for: .milliseconds(1200))
                // 이어서 넣으면 새 작업이 다시 보이므로, 취소된 작업은 지우지 않는다.
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) { isShowingAdded = false }
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
        .overlay {
            if movingItemID != nil {
                InboxCalendarOverlay(today: clock.today, month: $overlayMonth)
                    .transition(.opacity)
            }
        }
        .onDisappear {
            moveSession.end()
            movingItemID = nil
        }
    }

    private func row(_ item: Item) -> some View {
        InboxRowView(item: item)
            .contentShape(Rectangle())
            .modifier(InboxRowPress(
                canMove: !editMode.isEditing && !item.isCompleted,
                onTap: {
                    isInputFocused = false
                    editorMode = .edit(item)
                },
                onPress: { phase, point, window in
                    handlePress(phase, at: point, in: window, on: item)
                }
            ))
            .swipeActions(edge: .trailing) {
                Button("삭제", role: .destructive) {
                    delete(item)
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
        addedCount += 1
        newTitle = ""
        // 엔터를 치면 입력창이 포커스를 잃는다. 이번 차례와 다음 차례에 다시 포커스를 줘서 이어서 쓸 수 있게 한다.
        isInputFocused = true
        Task { isInputFocused = true }
    }

    /// 꾹 누르면 덮개 달력을 띄우고, 날짜 위에서 떼면 그 날로 넣는다. 미룰 때 남긴 모양(종일·시간, 길이)을 그대로 쓴다.
    private func handlePress(_ phase: RangePressGesture.Phase, at point: CGPoint, in window: UIWindow?, on item: Item) {
        switch phase {
        case .tap:
            isInputFocused = false
            editorMode = .edit(item)
        case .began:
            guard movingItemID == nil, let window else { return }
            InboxDropTip().invalidate(reason: .actionPerformed)
            toast.dismiss()
            isInputFocused = false
            overlayMonth = clock.today.monthIndex
            withAnimation(.easeOut(duration: 0.15)) {
                movingItemID = item.id
            }
            moveSession.begin(
                title: item.title,
                colorHex: item.category?.colorHex ?? CategoryPalette.uncategorizedHex,
                from: nil,
                at: point,
                in: window
            )
        case .changed:
            moveSession.update(to: point)
        case .ended:
            guard movingItemID == item.id else { return }
            let target = moveSession.finish(at: point)
            withAnimation(.easeOut(duration: 0.15)) {
                movingItemID = nil
            }
            guard let target, !item.isScheduled else { return }
            item.schedule(on: target, using: item.scheduleHint)
            try? modelContext.save()
            if let entry = item.calendarEntry() {
                CalendarDropState.shared.land(itemID: item.id, days: entry.startDay...entry.endDay)
            }
            onScheduled(target)
        case .cancelled:
            moveSession.end(animated: true)
            withAnimation(.easeOut(duration: 0.15)) {
                movingItemID = nil
            }
        }
    }

    /// 밀어서 지운다. 확인은 묻지 않고, 잠깐 뜨는 토스트로 되살릴 수 있다.
    private func delete(_ item: Item) {
        let snapshot = ItemSnapshot(item)
        modelContext.delete(item)
        try? modelContext.save()
        toast.show("‘\(snapshot.title)’ 삭제함", systemImage: "trash") { [modelContext] in
            modelContext.insert(snapshot.makeItem())
            try? modelContext.save()
        }
    }

    /// 편집 중에만 순서를 바꾼다. 편집 밖에서도 켜 두면 목록의 끌어 순서 바꾸기가 꾹 누르기와 겹친다.
    private func reorderAction(for pending: [Item]) -> ((IndexSet, Int) -> Void)? {
        guard editMode.isEditing else { return nil }
        return { source, destination in
            move(pending, from: source, to: destination)
        }
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

/// 행 누르기. 달력에 넣을 수 있는 행은 `WindowPressGesture` 하나가 탭(편집)과 꾹 누르기(달력에 넣기)를 받는다.
/// 완료한 항목과 순서를 바꾸는 편집 중에는 탭만 받는다.
private struct InboxRowPress: ViewModifier {
    let canMove: Bool
    let onTap: () -> Void
    let onPress: (RangePressGesture.Phase, CGPoint, UIWindow?) -> Void

    func body(content: Content) -> some View {
        if canMove {
            content.gesture(WindowPressGesture(onChange: onPress))
        } else {
            content.onTapGesture(perform: onTap)
        }
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
                BodySummaryLine(item: item)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
