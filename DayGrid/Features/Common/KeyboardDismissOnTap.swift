import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// `isActive`인 동안 화면의 입력창 밖(빈 곳, 제목 줄, 행 등)을 누르면 `onTap`을 부른다. 키보드를 내리는 데 쓴다.
///
/// - 누르기를 가로채지 않는다. 행 탭, 밀기, 버튼은 그대로 동작한다.
/// - 입력창 안을 누르면 부르지 않는다(커서 옮기기).
/// - 목록에 SwiftUI `onTapGesture`를 달면 입력창과 행 버튼까지 가로채므로, 이 뷰가 붙은 창에 UIKit 탭 제스처를 단다.
///   이 뷰가 창에서 빠지면(다른 탭) 제스처도 뗀다.
struct KeyboardDismissOnTap: UIViewRepresentable {
    let isActive: Bool
    let onTap: () -> Void

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: InstallerView, context: Context) {
        view.onTap = onTap
        view.isActive = isActive
    }

    static func dismantleUIView(_ view: InstallerView, coordinator: ()) {
        view.isActive = false
    }

    final class InstallerView: UIView {
        var onTap: () -> Void = {}
        var isActive = false {
            didSet { install() }
        }

        private lazy var recognizer: OutsideTextInputTapRecognizer = {
            let recognizer = OutsideTextInputTapRecognizer(target: self, action: #selector(handleTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesEnded = false
            return recognizer
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            install()
        }

        /// 켜져 있고 창에 있을 때만 창에 단다.
        private func install() {
            let host = isActive ? window : nil
            guard recognizer.view !== host else { return }
            recognizer.view?.removeGestureRecognizer(recognizer)
            host?.addGestureRecognizer(recognizer)
        }

        @objc private func handleTap() {
            onTap()
        }
    }
}

/// 입력창(`UITextInput`) 밖의 탭. 다른 제스처를 막지 않고, 다른 제스처에 막히지도 않는다.
final class OutsideTextInputTapRecognizer: UITapGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if touches.contains(where: { Self.isInTextInput($0.view) }) {
            state = .failed
        }
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    private static func isInTextInput(_ view: UIView?) -> Bool {
        var current = view
        while let candidate = current {
            if candidate is UITextInput {
                return true
            }
            current = candidate.superview
        }
        return false
    }
}
