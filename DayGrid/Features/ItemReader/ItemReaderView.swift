import DayGridCore
import SwiftData
import SwiftUI

/// 하루 상세에서 본문 버튼을 누르면 열리는 읽기 화면. 제목, 시간, 카테고리, 본문만 보여준다.
///
/// 고치지는 않지만 체크는 할 수 있다.
/// - 할일이면 제목 옆 체크박스로 완료를 켜고 끈다.
/// - 본문의 체크리스트(`- [ ]`)를 누르면 `MarkdownTaskList`로 본문 원문을 고쳐 저장한다.
struct ItemReaderView: View {
    let item: Item
    let timeText: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()
                MarkdownPreview(markdown: item.body ?? "") { index in
                    toggleTask(at: index)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .navigationTitle("본문")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            if item.isTask {
                Button {
                    item.toggleCompletion()
                    try? modelContext.save()
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(item.isCompleted ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(item.isCompleted ? "완료 취소" : "완료로 표시")
                .accessibilityIdentifier("reader.complete")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.title3.bold())
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                    .accessibilityIdentifier("reader.title")
                if !timeText.isEmpty {
                    Label(timeText, systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let category = item.category {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: category.colorHex))
                            .frame(width: 8, height: 8)
                        Text(category.name)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("reader.category")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func toggleTask(at index: Int) {
        guard let body = item.body, let toggled = MarkdownTaskList.toggle(at: index, in: body) else { return }
        item.body = toggled
        item.updatedAt = Date()
        try? modelContext.save()
    }
}
