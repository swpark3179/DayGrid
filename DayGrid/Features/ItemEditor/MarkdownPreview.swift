import SwiftUI
import UIKit
import WebKit

/// 마크다운 본문 미리보기. 번들의 `markdown/preview.html`(markdown-it + DOMPurify)을 띄우고 본문을 그린다.
/// 인터넷 없이 동작한다. 스크립트는 DOMPurify가 걸러 내고, 링크는 앱 밖(Safari 등)에서 연다.
///
/// `onToggleTask`를 주면 체크리스트를 누를 수 있다. 누른 체크의 순서(0부터)를 넘기므로,
/// 받는 쪽은 `MarkdownTaskList.toggle(at:in:)`으로 원문을 고친다. 주지 않으면 읽기만 한다.
struct MarkdownPreview: UIViewRepresentable {
    let markdown: String
    var onToggleTask: ((Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = []
        if onToggleTask != nil {
            configuration.userContentController.add(context.coordinator, name: Coordinator.toggleMessageName)
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.accessibilityIdentifier = "body.preview"
        context.coordinator.markdown = markdown
        context.coordinator.onToggleTask = onToggleTask
        if let page = Bundle.main.url(forResource: "preview", withExtension: "html", subdirectory: "markdown") {
            webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onToggleTask = onToggleTask
        context.coordinator.render(markdown, in: webView)
    }

    /// 메시지 처리기는 코디네이터를 붙잡고 있으므로, 화면이 사라질 때 떼어 낸다.
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.toggleMessageName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let toggleMessageName = "taskToggle"

        var markdown = ""
        var onToggleTask: ((Int) -> Void)?
        private var isLoaded = false
        private var renderedMarkdown: String?

        func render(_ markdown: String, in webView: WKWebView) {
            self.markdown = markdown
            guard isLoaded, renderedMarkdown != markdown else { return }
            renderedMarkdown = markdown
            webView.callAsyncJavaScript(
                "renderMarkdown(source); if (toggles) { enableTaskToggles(); } return true",
                arguments: ["source": markdown, "toggles": onToggleTask != nil],
                in: nil,
                in: .page,
                completionHandler: nil
            )
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            render(markdown, in: webView)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            if navigationAction.navigationType == .linkActivated {
                if let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "tel"].contains(scheme) {
                    _ = await UIApplication.shared.open(url)
                }
                return .cancel
            }
            // 미리보기 페이지 자신을 처음 여는 것만 허용한다.
            return url.isFileURL && !isLoaded ? .allow : .cancel
        }

        /// `preview.js`가 체크박스를 누를 때 보내는 체크 순서
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.toggleMessageName, let index = (message.body as? NSNumber)?.intValue else { return }
            onToggleTask?(index)
        }
    }
}
