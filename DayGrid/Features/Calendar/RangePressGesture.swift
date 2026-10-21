import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// 달력 격자의 탭과 꾹 누르기를 함께 받는 제스처.
///
/// - 짧게 누르고 떼면 `.tap`(하루 상세).
/// - 0.4초 동안 움직이지 않으면 기간 고르기를 시작한다(`.began` → `.changed` → `.ended`).
/// - 그 전에 12pt 넘게 움직이면 실패해서, 좌우로 밀면 달이 그대로 넘어간다.
///
/// 날짜 칸은 SwiftUI `Button`이 아니다(`WeekRowView`의 `DayHitTarget`). SwiftUI는 자식 제스처를 먼저 주므로,
/// 버튼이 누르기를 잡으면 이 제스처가 시작되지 못한다(PR #15 CI: 꾹 눌러 끌었더니 달이 넘어갔다).
/// 기간 고르기가 시작되면 손가락 아래의 스크롤 뷰(달 넘김 `TabView`)를 끝날 때까지 멈춘다.
struct RangePressGesture: UIGestureRecognizerRepresentable {
    enum Phase {
        case tap
        case began
        case changed
        case ended
        case cancelled
    }

    let onChange: (Phase, CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> DayPressRecognizer {
        DayPressRecognizer()
    }

    func handleUIGestureRecognizerAction(_ recognizer: DayPressRecognizer, context: Context) {
        let location = context.converter.localLocation
        switch recognizer.state {
        case .began:
            onChange(.began, location)
        case .changed:
            onChange(.changed, location)
        case .ended:
            onChange(recognizer.isTap ? .tap : .ended, location)
        case .cancelled:
            onChange(.cancelled, location)
        default:
            break
        }
    }
}

/// 하루 상세 목록 행의 탭과 꾹 누르기. 달력 격자와 같은 `DayPressRecognizer`를 쓰고, 위치는 창 좌표로 준다.
///
/// - 짧게 누르면 `.tap`(편집), 꾹 누르면 `.began` → `.changed` → `.ended`(다른 날로 옮기기).
/// - 그 전에 움직이면 실패해서 목록 스크롤과 행 밀기(스와이프 동작)에 양보한다.
/// - 행은 시트 안에 있고 놓을 곳은 시트 뒤의 달력이다. 두 계층이 같이 쓰는 창 좌표(`location(in: nil)`)로 잰다.
///   행 안의 버튼(체크박스, 본문 보기)은 SwiftUI가 먼저 받으므로 이 제스처가 시작되지 않는다.
struct WindowPressGesture: UIGestureRecognizerRepresentable {
    let onChange: (RangePressGesture.Phase, CGPoint, UIWindow?) -> Void

    func makeUIGestureRecognizer(context: Context) -> DayPressRecognizer {
        DayPressRecognizer()
    }

    func handleUIGestureRecognizerAction(_ recognizer: DayPressRecognizer, context: Context) {
        let location = recognizer.location(in: nil)
        let window = recognizer.view?.window
        switch recognizer.state {
        case .began:
            onChange(.began, location, window)
        case .changed:
            onChange(.changed, location, window)
        case .ended:
            onChange(recognizer.isTap ? .tap : .ended, location, window)
        case .cancelled:
            onChange(.cancelled, location, window)
        default:
            break
        }
    }
}

/// 한 손가락 누르기를 탭, 꾹 누르기(끌기 포함), 실패(달 넘김에 양보) 중 하나로 정한다.
final class DayPressRecognizer: UIGestureRecognizer {
    /// 이만큼 누르고 있으면 꾹 누르기
    static let minimumPressDuration: TimeInterval = 0.4
    /// 꾹 누르기가 시작되기 전에 이만큼 넘게 움직이면 실패(좌우 넘기기로 본다)
    static let allowableMovement: CGFloat = 12

    /// `.ended`가 짧은 탭이었는지
    private(set) var isTap = false

    private var startPoint: CGPoint = .zero
    private var pressTimer: Timer?
    private var pausedScrollViews: [UIScrollView] = []

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard (event.allTouches?.count ?? touches.count) == 1, let touch = touches.first else {
            // 두 손가락이면 탭도 기간 고르기도 아니다.
            if state == .began || state == .changed {
                state = .cancelled
            } else {
                fail()
            }
            return
        }
        guard state == .possible else { return }
        startPoint = touch.location(in: nil)
        pressTimer?.invalidate()
        pressTimer = Timer.scheduledTimer(withTimeInterval: Self.minimumPressDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pressTimerFired()
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first else { return }
        switch state {
        case .possible:
            let point = touch.location(in: nil)
            if hypot(point.x - startPoint.x, point.y - startPoint.y) > Self.allowableMovement {
                fail()
            }
        case .began, .changed:
            state = .changed
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        pressTimer?.invalidate()
        switch state {
        case .possible:
            isTap = true
            state = .ended
        case .began, .changed:
            state = .ended
        default:
            break
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        pressTimer?.invalidate()
        switch state {
        case .began, .changed:
            state = .cancelled
        default:
            fail()
        }
    }

    /// 끝나거나 실패하거나 뷰에서 떨어질 때 UIKit이 부른다. 액션이 오지 않은 경우에도 스크롤을 되살린다.
    override func reset() {
        super.reset()
        pressTimer?.invalidate()
        pressTimer = nil
        isTap = false
        resumeScrolling()
    }

    private func pressTimerFired() {
        guard state == .possible else { return }
        guard pauseScrolling() else {
            // 이미 달을 넘기는 중이면 기간 고르기를 시작하지 않는다.
            fail()
            return
        }
        state = .began
    }

    private func fail() {
        pressTimer?.invalidate()
        if state == .possible {
            state = .failed
        }
    }

    /// 손가락 아래 뷰부터 위로 올라가며 스크롤 뷰를 멈춘다. 붙은 뷰가 스크롤 뷰 밖에 있어도 찾도록 창에서 hit-test로 시작한다.
    /// 그중 하나가 이미 끌리는 중(달을 넘기는 중)이면 아무것도 멈추지 않고 `false`를 낸다.
    private func pauseScrolling() -> Bool {
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

    private func resumeScrolling() {
        for scrollView in pausedScrollViews {
            scrollView.isScrollEnabled = true
        }
        pausedScrollViews = []
    }
}
