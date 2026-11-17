import SwiftUI

/// 목록 행 앞의 표시. 할일이면 완료 체크박스, 아니면 카테고리 색 막대.
/// 체크하면 기호가 바뀌며 튀고, 완료로 바뀔 때만 성공 햅틱이 온다(`CompletionCheckmark`).
///
/// 취소선을 그은(보류·취소한) 할일은 체크박스 대신 ⊘가 보이고, 누르면 취소선을 지워 남은 할일로 돌린다.
/// 취소선을 그은 일정은 색 막대를 흐리게 그린다.
struct ItemMarker: View {
    let item: Item
    /// 작은 체크박스(하루 상세 타임라인의 짧은 칸)
    var compact = false

    var body: some View {
        if item.isTask {
            Button {
                // 제목의 취소선과 색도 함께 바뀌도록 애니메이션 안에서 바꾼다.
                withAnimation(.snappy) {
                    if item.isCancelled {
                        item.toggleCancellation()
                    } else {
                        item.toggleCompletion()
                    }
                }
            } label: {
                CompletionCheckmark(isDone: item.isCompleted, isCancelled: item.isCancelled, font: compact ? .callout : .title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(CompletionCheckmark.actionLabel(isDone: item.isCompleted, isCancelled: item.isCancelled))
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: item.category?.colorHex ?? CategoryPalette.uncategorizedHex).opacity(item.isCancelled ? 0.35 : 1))
                .frame(width: 4, height: 34)
        }
    }
}

extension View {
    /// 목록 행의 일정 제목 모양. 끝낸 할일과 취소선을 그은(보류·취소한) 일정은 줄을 긋고 흐리게 둔다.
    /// 취소선을 그은 것은 VoiceOver와 UI 테스트가 알 수 있게 값("취소선")을 단다.
    func itemTitleStyle(_ item: Item) -> some View {
        strikethrough(item.isStruckThrough)
            .foregroundStyle(item.isStruckThrough ? Color.secondary : Color.primary)
            .accessibilityValue(Text(verbatim: item.isCancelled ? "취소선" : ""))
    }
}

/// 취소선(보류·취소)을 긋거나 지우는 버튼. 하루 상세와 "나중에" 목록의 밀기, 타임라인 블록의 메뉴가 같이 쓴다.
/// 확인 없이 바로 저장한다. 행이 그 자리에 남아 바뀐 것이 보이므로 되돌리기 토스트는 띄우지 않는다.
/// 밀기 버튼은 다른 밀기 버튼처럼 글자만 둔다(`showsIcon == false`).
struct CancellationButton: View {
    let item: Item
    var showsIcon = true
    let onChange: () -> Void

    var body: some View {
        Button {
            withAnimation(.snappy) {
                item.toggleCancellation()
            }
            onChange()
        } label: {
            if showsIcon {
                Label(title, systemImage: item.isCancelled ? "arrow.uturn.backward" : "strikethrough")
            } else {
                Text(title)
            }
        }
        // 밀기 버튼의 색. 메뉴에서는 쓰이지 않는다.
        .tint(.gray)
    }

    private var title: String {
        item.isCancelled ? "취소선 지우기" : "취소선 긋기"
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
/// 취소선을 그은 할일(`isCancelled`)은 ⊘로 그린다.
struct CompletionCheckmark: View {
    let isDone: Bool
    var isCancelled = false
    var font: Font = .title3

    var body: some View {
        Image(systemName: symbolName)
            .font(font)
            .foregroundStyle(isDone ? Color.accentColor : Color.secondary)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: isDone)
            .sensoryFeedback(.success, trigger: isDone) { _, done in done }
    }

    private var symbolName: String {
        if isCancelled { return "slash.circle" }
        return isDone ? "checkmark.circle.fill" : "circle"
    }

    /// 체크박스를 눌렀을 때 하는 일(VoiceOver 라벨). 취소선을 그은 할일은 취소선을 지운다.
    static func actionLabel(isDone: Bool, isCancelled: Bool) -> String {
        if isCancelled { return "취소선 지우기" }
        return isDone ? "완료 취소" : "완료로 표시"
    }
}
