import DayGridCore
import SwiftUI
import UIKit

/// 마크다운 본문 편집기. 키보드 위에 서식 툴바(제목, 굵게, 기울임, 목록, 체크리스트, 링크, 인용, 코드)를 단다.
/// 서식 변환은 Core `MarkdownFormatter`가 하고, 여기서는 그 결과를 텍스트 뷰에 적용한다(실행 취소가 된다).
struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.backgroundColor = .clear
        textView.text = text
        textView.delegate = context.coordinator
        textView.inputAccessoryView = context.coordinator.makeToolbar()
        textView.accessibilityIdentifier = "body.editor"
        context.coordinator.textView = textView
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.text = $text
        if textView.text != text {
            textView.text = text
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        weak var textView: UITextView?

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }

        func makeToolbar() -> UIToolbar {
            let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            var items: [UIBarButtonItem] = []
            for (index, style) in MarkdownStyle.allCases.enumerated() {
                if index > 0 {
                    items.append(.flexibleSpace())
                }
                let item = UIBarButtonItem(
                    image: UIImage(systemName: Self.symbol(for: style)),
                    style: .plain,
                    target: self,
                    action: #selector(applyStyle(_:))
                )
                item.tag = index
                item.accessibilityLabel = Self.label(for: style)
                items.append(item)
            }
            toolbar.items = items
            toolbar.sizeToFit()
            return toolbar
        }

        @objc private func applyStyle(_ sender: UIBarButtonItem) {
            guard let textView, MarkdownStyle.allCases.indices.contains(sender.tag) else { return }
            let style = MarkdownStyle.allCases[sender.tag]
            let edit = MarkdownFormatter.edit(style, text: textView.text, selection: textView.selectedRange)
            guard let start = textView.position(from: textView.beginningOfDocument, offset: edit.range.location),
                  let end = textView.position(from: start, offset: edit.range.length),
                  let range = textView.textRange(from: start, to: end)
            else { return }
            textView.replace(range, withText: edit.replacement)
            textView.selectedRange = edit.selection
            text.wrappedValue = textView.text
        }

        private static func symbol(for style: MarkdownStyle) -> String {
            switch style {
            case .heading: "number"
            case .bold: "bold"
            case .italic: "italic"
            case .bulletList: "list.bullet"
            case .checklist: "checklist"
            case .link: "link"
            case .quote: "text.quote"
            case .code: "chevron.left.forwardslash.chevron.right"
            }
        }

        private static func label(for style: MarkdownStyle) -> String {
            switch style {
            case .heading: "제목"
            case .bold: "굵게"
            case .italic: "기울임"
            case .bulletList: "목록"
            case .checklist: "체크리스트"
            case .link: "링크"
            case .quote: "인용"
            case .code: "코드"
            }
        }
    }
}
