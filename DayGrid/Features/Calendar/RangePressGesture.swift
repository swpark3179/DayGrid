import SwiftUI
import UIKit

/// 달력 격자를 꾹 누른 채 끌어 기간을 고르는 제스처.
///
/// UIKit 길게 누르기(`UILongPressGestureRecognizer`)는 인식된 뒤에도 손가락 위치를 계속 알려 준다.
/// 먼저 인식되면 같은 터치로 페이지 넘김(스크롤 pan)이 시작되지 않으므로, 평소의 좌우 넘기기와 부딪히지 않는다.
/// 짧게 누르면 인식되지 않으므로 날짜 칸의 탭(하루 상세)은 그대로 된다.
struct RangePressGesture: UIGestureRecognizerRepresentable {
    enum Phase {
        case began
        case changed
        case ended
        case cancelled
    }

    var minimumDuration: TimeInterval = 0.4
    let onChange: (Phase, CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = minimumDuration
        // 누르는 동안 이만큼 넘게 움직이면 길게 누르기가 아니다(좌우 넘기기로 본다).
        recognizer.allowableMovement = 12
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let location = context.converter.localLocation
        switch recognizer.state {
        case .began:
            onChange(.began, location)
        case .changed:
            onChange(.changed, location)
        case .ended:
            onChange(.ended, location)
        case .cancelled, .failed:
            onChange(.cancelled, location)
        default:
            break
        }
    }
}
