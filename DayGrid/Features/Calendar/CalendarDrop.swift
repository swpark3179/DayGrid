import DayGridCore
import Foundation
import Observation
import SwiftUI
import UIKit

/// 달력 위에서 일정을 꾹 눌러 끄는 동안의 상태. 강조할 날짜와 가장자리에서 달 넘기기를 함께 쓴다.
///
/// - 하루 상세 → 다른 날(Phase 14), "나중에" → 달력(Phase 15) 모두 손가락 위치를 창 좌표로 받아
///   `hover(atWindowPoint:)`로 날짜 칸을 찾는다. 누르기는 목록 행의 `WindowPressGesture`가 끝까지 받는다.
/// - 달 페이지마다 `CalendarPageAnchor`가 격자 뷰와 그 페이지의 달 넘기기를 등록해 둔다.
///   행(시트나 "나중에" 목록)과 달력은 서로 다른 SwiftUI 계층이라 창 좌표로 맞춘다.
@MainActor
@Observable
final class CalendarDropState {
    static let shared = CalendarDropState()

    /// 이 너비 안의 왼쪽·오른쪽 가장자리에 머무르면 달을 넘긴다.
    nonisolated static let edgeWidth: CGFloat = 28

    /// 손가락 아래 날짜(그 칸을 강조한다)
    var target: LocalDate?

    @ObservationIgnored private var edge = 0
    @ObservationIgnored private var edgeTask: Task<Void, Never>?
    @ObservationIgnored private var pages: [ObjectIdentifier: Page] = [:]
    @ObservationIgnored private var lastWindowPoint: CGPoint?

    private struct Page {
        weak var view: UIView?
        var visibleDays: ClosedRange<LocalDate>
        /// 이 페이지가 들어 있는 달력을 이전(-1)·다음(+1) 달로 넘긴다.
        var onPage: @MainActor (Int) -> Void
    }

    /// 왼쪽·오른쪽 가장자리(`edge` -1, +1)에 0.8초 머무를 때마다 이전·다음 달로 넘긴다.
    private func hover(edge newEdge: Int, onPage: @escaping @MainActor (Int) -> Void) {
        guard newEdge != edge else { return }
        edge = newEdge
        edgeTask?.cancel()
        guard newEdge != 0 else { return }
        edgeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled, let self, self.edge == newEdge else { return }
                onPage(newEdge)
            }
        }
    }

    func endHover() {
        target = nil
        edge = 0
        edgeTask?.cancel()
        edgeTask = nil
        lastWindowPoint = nil
    }

    // MARK: - 창 좌표로 날짜 찾기

    /// 달 페이지의 격자 뷰를 등록한다. 같은 뷰를 다시 넣으면 보이는 날짜와 달 넘기기만 바꾼다.
    func registerPage(_ view: UIView, visibleDays: ClosedRange<LocalDate>, onPage: @escaping @MainActor (Int) -> Void) {
        pages = pages.filter { $0.value.view != nil }
        pages[ObjectIdentifier(view)] = Page(view: view, visibleDays: visibleDays, onPage: onPage)
    }

    func unregisterPage(_ view: UIView) {
        pages[ObjectIdentifier(view)] = nil
    }

    /// 창 좌표 `point` 아래의 날짜와 가장자리(-1 왼쪽, 0, +1 오른쪽). 화면에 보이는 달 페이지 밖이면 `nil`.
    /// 페이지 넘김(`TabView`)의 옆 달은 화면 밖에 있으므로, 손가락이 들어 있는 페이지는 지금 보이는 달 하나다.
    func day(atWindowPoint point: CGPoint) -> (day: LocalDate, edge: Int)? {
        page(atWindowPoint: point).map { (day: $0.day, edge: $0.edge) }
    }

    private func page(atWindowPoint point: CGPoint) -> (day: LocalDate, edge: Int, onPage: @MainActor (Int) -> Void)? {
        for page in pages.values {
            guard let view = page.view, view.window != nil, !Self.isHidden(view) else { continue }
            let frame = view.convert(view.bounds, to: nil)
            guard frame.contains(point),
                  let day = MonthLayout.day(
                      atX: point.x - frame.minX,
                      y: point.y - frame.minY,
                      width: frame.width,
                      height: frame.height,
                      in: page.visibleDays
                  )
            else { continue }
            let edge = point.x < frame.minX + Self.edgeWidth ? -1 : (point.x > frame.maxX - Self.edgeWidth ? 1 : 0)
            return (day, edge, page.onPage)
        }
        return nil
    }

    /// 창에 남아 있지만 보이지 않는 달력(뷰나 그 위의 뷰가 숨겨짐)은 놓을 곳이 아니다.
    private static func isHidden(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current {
            if candidate.isHidden {
                return true
            }
            current = candidate.superview
        }
        return false
    }

    /// 끄는 손가락이 움직일 때. 그 아래 날짜를 강조하고, 가장자리에 머무르면 그 페이지의 달력을 넘긴다.
    /// 달을 넘긴 뒤에는 손가락이 그대로여도 새 달의 날짜로 강조를 바꾼다.
    @discardableResult
    func hover(atWindowPoint point: CGPoint) -> LocalDate? {
        lastWindowPoint = point
        let hit = page(atWindowPoint: point)
        // 손가락이 움직일 때마다 달력을 다시 그리지 않도록 날짜가 바뀔 때만 넣는다.
        if target != hit?.day {
            target = hit?.day
        }
        let onPage = hit?.onPage
        hover(edge: hit?.edge ?? 0) { [weak self] delta in
            guard let self else { return }
            onPage?(delta)
            Task { @MainActor [weak self] in
                // 페이지 넘김 애니메이션이 끝난 뒤의 위치로 다시 잰다.
                try? await Task.sleep(for: .milliseconds(450))
                guard let self, let point = self.lastWindowPoint else { return }
                let day = self.day(atWindowPoint: point)?.day
                if self.target != day {
                    self.target = day
                }
            }
        }
        return hit?.day
    }
}

/// 달 페이지 격자와 같은 크기의 빈 UIKit 뷰. 꾹 눌러 끌 때(하루 상세에서 옮기기, "나중에"에서 넣기) `CalendarDropState`가
/// 이 뷰의 창 위치로 손가락 아래 날짜 칸을 찾고, 가장자리에 머무르면 `onPage`로 이 페이지가 든 달력을 넘긴다.
/// 누르기를 받지 않는다(격자의 누르기는 `RangePressGesture`가 받는다).
struct CalendarPageAnchor: UIViewRepresentable {
    let visibleDays: ClosedRange<LocalDate>
    let onPage: @MainActor (Int) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        CalendarDropState.shared.registerPage(view, visibleDays: visibleDays, onPage: onPage)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        CalendarDropState.shared.registerPage(view, visibleDays: visibleDays, onPage: onPage)
    }

    static func dismantleUIView(_ view: UIView, coordinator: ()) {
        CalendarDropState.shared.unregisterPage(view)
    }
}
