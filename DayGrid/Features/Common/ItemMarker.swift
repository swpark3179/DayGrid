import SwiftUI

/// 목록 행 앞의 표시. 할일이면 완료 체크박스, 아니면 카테고리 색 막대.
struct ItemMarker: View {
    let item: Item
    /// 작은 체크박스(하루 상세 타임라인의 짧은 칸)
    var compact = false

    var body: some View {
        if item.isTask {
            Button {
                item.toggleCompletion()
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(compact ? .callout : .title3)
                    .foregroundStyle(item.isCompleted ? Color.accentColor : Color.secondary)
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
