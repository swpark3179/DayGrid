import SwiftUI

/// 목록 행 앞의 표시. 할일이면 완료 체크박스, 아니면 카테고리 색 막대.
/// 체크하면 기호가 바뀌며 튀고, 완료로 바뀔 때만 성공 햅틱이 온다(`CompletionCheckmark`).
struct ItemMarker: View {
    let item: Item
    /// 작은 체크박스(하루 상세 타임라인의 짧은 칸)
    var compact = false

    var body: some View {
        if item.isTask {
            Button {
                // 제목의 취소선과 색도 함께 바뀌도록 애니메이션 안에서 바꾼다.
                withAnimation(.snappy) {
                    item.toggleCompletion()
                }
            } label: {
                CompletionCheckmark(isDone: item.isCompleted, font: compact ? .callout : .title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(item.isCompleted ? "완료 취소" : "완료로 표시")
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: item.category?.colorHex ?? CategoryPalette.uncategorizedHex))
                .frame(width: 4, height: 34)
        }
    }
}

/// 본문이 있으면 문서 아이콘과 첫 줄을 한 줄로 보여준다.
struct BodySummaryLine: View {
    let item: Item

    var body: some View {
        if let summary = item.bodySummary {
            Label(summary, systemImage: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// 완료 체크 기호. 바뀔 때 기호가 갈아 끼워지며 튄다. 완료로 바뀔 때만 성공 햅틱을 준다.
/// 할일(`ItemMarker`), 반복 할일(`RecurringTaskRow`), 읽기 화면(`ItemReaderView`)이 같이 쓴다.
struct CompletionCheckmark: View {
    let isDone: Bool
    var font: Font = .title3

    var body: some View {
        Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
            .font(font)
            .foregroundStyle(isDone ? Color.accentColor : Color.secondary)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: isDone)
            .sensoryFeedback(.success, trigger: isDone) { _, done in done }
    }
}
