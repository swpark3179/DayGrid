import DayGridCore
import SwiftUI

/// 본문 화면. 위쪽 세그먼트로 마크다운 편집과 미리보기를 바꾼다.
/// 본문이 있으면 미리보기로, 비어 있으면 편집으로 시작한다.
struct BodyEditorView: View {
    enum Mode: Hashable {
        case edit
        case preview
    }

    @Binding var text: String
    @State private var mode: Mode

    init(text: Binding<String>) {
        _text = text
        _mode = State(initialValue: Self.isBlank(text.wrappedValue) ? .edit : .preview)
    }

    var body: some View {
        Group {
            switch mode {
            case .edit:
                MarkdownTextView(text: $text)
            case .preview:
                if Self.isBlank(text) {
                    ContentUnavailableView(
                        "본문 없음",
                        systemImage: "doc.text",
                        description: Text("편집에서 마크다운으로 적으면 여기서 미리 볼 수 있습니다.")
                    )
                } else {
                    MarkdownPreview(markdown: text)
                }
            }
        }
        .navigationTitle("본문")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("보기", selection: $mode) {
                    Text("편집").tag(Mode.edit)
                    Text("미리보기").tag(Mode.preview)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .accessibilityIdentifier("body.mode")
            }
        }
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension Item {
    /// 목록 행에 보일 본문 첫 줄. 본문이 없으면 `nil`.
    var bodySummary: String? {
        body.flatMap { MarkdownSummary.firstLine(of: $0) }
    }
}
