import SwiftUI
import UIKit

/// 설정의 테마를 이 뷰가 붙은 창에 건다(`overrideUserInterfaceStyle`).
///
/// - 창에 걸기 때문에 시트, 창에 붙인 끌기 미리보기(`ItemMoveSession`), 본문 미리보기(WKWebView)도 같이 바뀐다.
/// - SwiftUI `preferredColorScheme`은 쓰지 않는다. 다크·라이트에서 nil(시스템)로 되돌려도 바로 돌아오지 않는 경우가 있다.
struct WindowAppearance: UIViewRepresentable {
    let appearance: AppAppearance

    func makeUIView(context: Context) -> StyleView {
        let view = StyleView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: StyleView, context: Context) {
        view.style = appearance.userInterfaceStyle
    }

    final class StyleView: UIView {
        var style: UIUserInterfaceStyle = .unspecified {
            didSet { apply() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        private func apply() {
            guard let window, window.overrideUserInterfaceStyle != style else { return }
            window.overrideUserInterfaceStyle = style
        }
    }
}
