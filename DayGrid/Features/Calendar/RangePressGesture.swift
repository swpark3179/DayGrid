import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// 달력 격자를 꾹 누른 채 끌어 기간을 고르는 제스처.
///
/// UIKit 길게 누르기(`UILongPressGestureRecognizer`)는 인식된 뒤에도 손가락 위치를 계속 알려 준다.
/// 짧게 누르면 인식되지 않으므로 날짜 칸의 탭(하루 상세)은 그대로 된다.
/// 인식되면 손가락 아래의 스크롤 뷰(달 넘김 `TabView`)를 끝날 때까지 멈춘다. SwiftUI 제스처는 스크롤과 함께 인식되므로,
/// 멈추지 않으면 끄는 동안 달이 넘어간다(PR #15 CI: 10/21 → 10/23으로 끌었더니 9월로 넘어갔다).
struct RangePressGesture: UIGestureRecognizerRepresentable {
    enum Phase {
        case began
        case changed
        case ended
        case cancelled
    }

    var minimumDuration: TimeInterval = 0.4
    let onChange: (Phase, CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> RangeLongPressRecognizer {
        let recognizer = RangeLongPressRecognizer()
        recognizer.minimumPressDuration = minimumDuration
        // 누르는 동안 이만큼 넘게 움직이면 길게 누르기가 아니다(좌우 넘기기로 본다).
        recognizer.allowableMovement = 12
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: RangeLongPressRecognizer, context: Context) {
        let location = context.converter.localLocation
        switch recognizer.state {
        case .began:
            guard recognizer.pauseScrolling() else {
                // 이미 달을 넘기는 중이면 기간 고르기를 시작하지 않는다.
                recognizer.cancel()
                return
            }
            onChange(.began, location)
        case .changed:
            onChange(.changed, location)
        case .ended:
            recognizer.resumeScrolling()
            onChange(.ended, location)
        case .cancelled, .failed:
            recognizer.resumeScrolling()
            onChange(.cancelled, location)
        default:
            break
        }
    }
}

/// 길게 누르는 동안 멈춘 스크롤 뷰를 기억했다가 끝나면 다시 켠다.
final class RangeLongPressRecognizer: UILongPressGestureRecognizer {
    private var pausedScrollViews: [UIScrollView] = []

    /// 손가락 아래 뷰부터 위로 올라가며 스크롤 뷰를 멈춘다. 붙은 뷰가 스크롤 뷰 밖에 있어도 찾도록 창에서 hit-test로 시작한다.
    /// 그중 하나가 이미 끌리는 중(달을 넘기는 중)이면 아무것도 멈추지 않고 `false`를 낸다.
    func pauseScrolling() -> Bool {
        resumeScrolling()
        guard let window = view?.window else { return true }
        var scrollViews: [UIScrollView] = []
        var current = window.hitTest(location(in: window), with: nil) ?? view
        while let candidate = current {
            if let scrollView = candidate as? UIScrollView, scrollView.isScrollEnabled {
                scrollViews.append(scrollView)
            }
            current = candidate.superview
        }
        guard !scrollViews.contains(where: \.isDragging) else { return false }
        for scrollView in scrollViews {
            scrollView.isScrollEnabled = false
        }
        pausedScrollViews = scrollViews
        return true
    }

    func resumeScrolling() {
        for scrollView in pausedScrollViews {
            scrollView.isScrollEnabled = true
        }
        pausedScrollViews = []
    }

    /// 진행 중인 길게 누르기를 취소한다(액션이 `.cancelled`로 한 번 더 온다).
    func cancel() {
        isEnabled = false
        isEnabled = true
    }

    /// 끝나거나 취소되거나 뷰에서 떨어질 때 UIKit이 부른다. 액션이 오지 않은 경우에도 스크롤을 되살린다.
    override func reset() {
        super.reset()
        resumeScrolling()
    }
}
