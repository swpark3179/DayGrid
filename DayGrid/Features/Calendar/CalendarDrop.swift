import DayGridCore
import Foundation
import Observation
import SwiftUI
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

/// "나중에"에서 달력으로 끄는 동안의 상태. 끌기를 시작하면 항목 id를 넣고, 달력에 놓으면 꺼낸다.
/// 놓을 때 데이터를 비동기로 읽지 않으려고, 같은 앱 안의 끌기는 id를 여기에 둔다.
@MainActor
@Observable
final class CalendarDropState {
    static let shared = CalendarDropState()

    /// 손가락 아래 날짜(그 칸을 강조한다)
    var target: LocalDate?

    @ObservationIgnored private var draggedItemID: UUID?
    @ObservationIgnored private var startedAt = Date.distantPast
    @ObservationIgnored private var edge = 0
    @ObservationIgnored private var edgeTask: Task<Void, Never>?

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
        let edgeWidth = 28.0
        let x = info.location.x
        let edge = x < edgeWidth ? -1 : (x > size.width - edgeWidth ? 1 : 0)
        state.hover(edge: edge, onPage: onPage)
    }

    private func day(at point: CGPoint) -> LocalDate? {
        MonthLayout.day(atX: point.x, y: point.y, width: size.width, height: size.height, in: visibleDays)
    }
}
