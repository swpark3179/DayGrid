import CoreGraphics
import Testing
@testable import DayGrid

/// 하루 상세에서 꾹 눌러 옮기는 동안 화면 맨 위 가운데에 뜨는 취소 표시(X)의 자리.
struct ItemMoveSessionTests {
    /// 393×852 창(iPhone 16 Pro 크기), 상태 막대(다이내믹 아일랜드) 높이 59
    private let bounds = CGRect(x: 0, y: 0, width: 393, height: 852)
    private let safeAreaTop: CGFloat = 59

    @Test func theCancelMarkSitsAtTheTopCenterBelowTheStatusBar() {
        let center = ItemMoveSession.cancelMarkCenter(in: bounds, safeAreaTop: safeAreaTop)
        #expect(center == CGPoint(x: 196.5, y: 85))
    }

    @Test func droppingNearTheCancelMarkOrAtTheVeryTopCancels() {
        let zone = ItemMoveSession.cancelZone(in: bounds, safeAreaTop: safeAreaTop)
        #expect(zone.contains(CGPoint(x: 196.5, y: 85)), "표시 위")
        #expect(zone.contains(CGPoint(x: 150, y: 110)), "표시 둘레")
        #expect(zone.contains(CGPoint(x: 196.5, y: 2)), "화면 맨 위 끝")
        #expect(!zone.contains(CGPoint(x: 40, y: 85)), "머리 줄 왼쪽의 연·월")
        #expect(!zone.contains(CGPoint(x: 360, y: 85)), "머리 줄 오른쪽의 버튼")
        #expect(!zone.contains(CGPoint(x: 196.5, y: 140)), "요일 줄 아래의 날짜 칸")
    }
}
