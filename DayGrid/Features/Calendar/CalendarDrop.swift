import DayGridCore
import Foundation
import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "나중에" 항목을 끌 때 싣는 데이터. 이 앱 안에서만 보이는 형식이라 다른 앱의 글자가 달력에 놓이지 않는다.
enum InboxDragPayload {
    static let type = UTType(exportedAs: "io.github.swpark3179.DayGrid.inbox-item")

    static func provider(for id: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = Data(id.uuidString.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }
}

/// 달력으로 끄는 동안의 상태. 강조할 날짜와 가장자리에서 달 넘기기를 함께 쓴다.
///
/// - "나중에" → 달력(시스템 끌어 놓기): 끌기를 시작하면 항목 id를 넣고, 달력에 놓으면 꺼낸다.
///   놓을 때 데이터를 비동기로 읽지 않으려고, 같은 앱 안의 끌기는 id를 여기에 둔다.
/// - 하루 상세 → 다른 날(꾹 눌러 옮기기): 손가락 위치를 창 좌표로 받아 `hover(atWindowPoint:)`로 날짜 칸을 찾는다.
///   달 페이지마다 `CalendarPageAnchor`가 격자 뷰를 등록해 둔다. 시트와 달력은 서로 다른 SwiftUI 계층이라 창 좌표로 맞춘다.
@MainActor
@Observable
final class CalendarDropState {
    static let shared = CalendarDropState()

    /// 이 너비 안의 왼쪽·오른쪽 가장자리에 머무르면 달을 넘긴다.
    nonisolated static let edgeWidth: CGFloat = 28

    /// 손가락 아래 날짜(그 칸을 강조한다)
    var target: LocalDate?

    /// 하루 상세에서 옮기는 중 가장자리에 머무를 때 달을 넘기는 동작. 달력 탭이 넣는다.
    @ObservationIgnored var onPage: (@MainActor (Int) -> Void)?

    @ObservationIgnored private var draggedItemID: UUID?
    @ObservationIgnored private var startedAt = Date.distantPast
    @ObservationIgnored private var edge = 0
    @ObservationIgnored private var edgeTask: Task<Void, Never>?
    @ObservationIgnored private var pages: [ObjectIdentifier: Page] = [:]
    @ObservationIgnored private var lastWindowPoint: CGPoint?

    private struct Page {
        weak var view: UIView?
        var visibleDays: ClosedRange<LocalDate>
    }

    func begin(itemID: UUID, now: Date = Date()) {
        draggedItemID = itemID
        startedAt = now
    }

    /// 놓을 때 한 번만 꺼낸다. 오래전에 시작한 끌기(취소된 끌기)는 버린다.
    func takeItemID(now: Date = Date()) -> UUID? {
        defer { draggedItemID = nil }
        guard now.timeIntervalSince(startedAt) < 300 else { return nil }
        return draggedItemID
    }

    /// 왼쪽·오른쪽 가장자리(`edge` -1, +1)에 0.8초 머무를 때마다 이전·다음 달로 넘긴다.
    func hover(edge newEdge: Int, onPage: @escaping @MainActor (Int) -> Void) {
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

    // MARK: - 하루 상세에서 꾹 눌러 옮기기

    /// 달 페이지의 격자 뷰를 등록한다. 같은 뷰를 다시 넣으면 보이는 날짜만 바꾼다.
    func registerPage(_ view: UIView, visibleDays: ClosedRange<LocalDate>) {
        pages = pages.filter { $0.value.view != nil }
        pages[ObjectIdentifier(view)] = Page(view: view, visibleDays: visibleDays)
    }

    func unregisterPage(_ view: UIView) {
        pages[ObjectIdentifier(view)] = nil
    }

    /// 창 좌표 `point` 아래의 날짜와 가장자리(-1 왼쪽, 0, +1 오른쪽). 화면에 있는 달 페이지 밖이면 `nil`.
    /// 페이지 넘김(`TabView`)의 옆 달은 화면 밖에 있으므로, 손가락이 들어 있는 페이지는 지금 보이는 달 하나다.
    func day(atWindowPoint point: CGPoint) -> (day: LocalDate, edge: Int)? {
        for page in pages.values {
            guard let view = page.view, view.window != nil else { continue }
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
            return (day, edge)
        }
        return nil
    }

    /// 하루 상세에서 끄는 손가락이 움직일 때. 그 아래 날짜를 강조하고, 가장자리에 머무르면 `onPage`로 달을 넘긴다.
    /// 달을 넘긴 뒤에는 손가락이 그대로여도 새 달의 날짜로 강조를 바꾼다.
    @discardableResult
    func hover(atWindowPoint point: CGPoint) -> LocalDate? {
        lastWindowPoint = point
        let hit = day(atWindowPoint: point)
        // 손가락이 움직일 때마다 달력을 다시 그리지 않도록 날짜가 바뀔 때만 넣는다.
        if target != hit?.day {
            target = hit?.day
        }
        hover(edge: hit?.edge ?? 0) { [weak self] delta in
            guard let self else { return }
            self.onPage?(delta)
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

/// 달 페이지 격자와 같은 크기의 빈 UIKit 뷰. 하루 상세에서 꾹 눌러 옮길 때 `CalendarDropState`가
/// 이 뷰의 창 위치로 손가락 아래 날짜 칸을 찾는다. 누르기를 받지 않는다(격자의 누르기는 `RangePressGesture`가 받는다).
struct CalendarPageAnchor: UIViewRepresentable {
    let visibleDays: ClosedRange<LocalDate>

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        CalendarDropState.shared.registerPage(view, visibleDays: visibleDays)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        CalendarDropState.shared.registerPage(view, visibleDays: visibleDays)
    }

    static func dismantleUIView(_ view: UIView, coordinator: ()) {
        CalendarDropState.shared.unregisterPage(view)
    }
}

/// 달력 한 달 페이지에 "나중에" 항목을 놓는 곳. 위치는 Core `MonthLayout.day(atX:…)`로 날짜 칸으로 바꾼다.
struct CalendarDropDelegate: DropDelegate {
    let size: CGSize
    let visibleDays: ClosedRange<LocalDate>
    let state: CalendarDropState
    let onPage: @MainActor (Int) -> Void
    let onDrop: (UUID, LocalDate) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [InboxDragPayload.type])
    }

    func dropEntered(info: DropInfo) {
        update(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        state.endHover()
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { state.endHover() }
        guard let date = day(at: info.location), let id = state.takeItemID() else { return false }
        onDrop(id, date)
        return true
    }

    private func update(_ info: DropInfo) {
        state.target = day(at: info.location)
        let edgeWidth = CalendarDropState.edgeWidth
        let x = info.location.x
        let edge = x < edgeWidth ? -1 : (x > size.width - edgeWidth ? 1 : 0)
        state.hover(edge: edge, onPage: onPage)
    }

    private func day(at point: CGPoint) -> LocalDate? {
        MonthLayout.day(atX: point.x, y: point.y, width: size.width, height: size.height, in: visibleDays)
    }
}
