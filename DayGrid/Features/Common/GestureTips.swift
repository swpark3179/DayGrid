import SwiftUI
import TipKit

/// 꾹 누르기로만 할 수 있는 동작을 처음 한 번 알려 주는 팁(TipKit). 직접 해 보면 그 팁은 닫힌다(`invalidate(reason: .actionPerformed)`).
///
/// - 팁은 `DayGridApp`에서 `Tips.configure()`로 켠다.
/// - UI 테스트와 단위 테스트에서는 숨긴다. 스크린샷과 달력 칸 위치가 바뀌지 않게 하려는 것이다.
///   팁 스크린샷만 `-UITestShowTips`로 보인다(`LaunchOptions.showsTips`).

/// 달력: 꾹 눌러 끌면 기간 일정
struct RangePressTip: Tip {
    var title: Text { Text("꾹 눌러 기간 일정 만들기") }
    var message: Text? { Text("날짜를 꾹 누른 채 다른 날까지 끌면 그 기간의 종일 일정이 생깁니다. 움직이지 않고 떼면 그 날 새 일정입니다.") }
    var image: Image? { Image(systemName: "hand.tap") }
}

/// 하루 상세: 꾹 눌러 다른 날로 옮기기
struct MoveItemTip: Tip {
    var title: Text { Text("꾹 눌러 다른 날로 옮기기") }
    var message: Text? { Text("일정을 꾹 누른 채 달력의 다른 날에 놓으면 그 날로 옮깁니다. 시각과 길이는 그대로입니다.") }
    var image: Image? { Image(systemName: "arrow.up.and.down.and.arrow.left.and.right") }
}

/// "나중에": 꾹 눌러 달력에 넣기
struct InboxDropTip: Tip {
    var title: Text { Text("꾹 눌러 달력에 넣기") }
    var message: Text? { Text("항목을 꾹 누르면 달력이 나옵니다. 넣을 날짜 위에서 손을 떼세요.") }
    var image: Image? { Image(systemName: "calendar.badge.plus") }
}
