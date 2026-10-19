import SwiftUI
import UIKit
import WebKit

/// 마크다운 본문 미리보기. 번들의 `markdown/preview.html`(markdown-it + DOMPurify)을 띄우고 본문을 그린다.
/// 인터넷 없이 동작한다. 스크립트는 DOMPurify가 걸러 내고, 링크는 앱 밖(Safari 등)에서 연다.
struct MarkdownPreview: UIViewRepresentable {
    let markdown: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.accessibilityIdentifier = "body.preview"
        context.coordinator.markdown = markdown
        if let page = Bundle.main.url(forResource: "preview", withExtension: "html", subdirectory: "markdown") {
            webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.render(markdown, in: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var markdown = ""
        private var isLoaded = false
        private var renderedMarkdown: String?

        func render(_ markdown: String, in webView: WKWebView) {
            self.markdown = markdown
            guard isLoaded, renderedMarkdown != markdown else { return }
            renderedMarkdown = markdown
            webView.callAsyncJavaScript(
                "return renderMarkdown(source)",
                arguments: ["source": markdown],
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
    }
}
