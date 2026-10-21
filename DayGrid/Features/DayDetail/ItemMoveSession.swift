import DayGridCore
import SwiftUI
import UIKit

/// 하루 상세에서 일정을 꾹 눌러 다른 날로 옮기는 동안의 미리보기와 놓을 날짜.
///
/// - 미리보기는 창 맨 위에 붙인다. 시트 안의 SwiftUI 뷰는 시트 밖에 그릴 수 없어서다.
/// - 손가락 아래 날짜는 `CalendarDropState.hover(atWindowPoint:)`가 찾고, 달력이 그 칸을 강조한다.
/// - 손가락을 거의 움직이지 않고 놓으면 옮기지 않는다(꾹 눌렀다 떼기만 해도 아래 날짜로 옮겨지지 않게).
@MainActor
final class ItemMoveSession {
    /// 이만큼 넘게 움직여야 놓았을 때 옮긴다.
    static let minimumTravel: CGFloat = 16
    /// 미리보기 크기. 날짜 글자가 바뀌어도 크기가 그대로이도록 고정한다.
    static let previewSize = CGSize(width: 240, height: 56)

    private let dropState = CalendarDropState.shared
    private var preview: UIHostingController<ItemMovePreview>?
    private var originalDate: LocalDate?
    private var startPoint = CGPoint.zero
    private var hasMoved = false
    private var lastTarget: LocalDate?
    private let selection = UISelectionFeedbackGenerator()

    func begin(title: String, colorHex: String, from date: LocalDate, at point: CGPoint, in window: UIWindow) {
        end()
        originalDate = date
        startPoint = point
        hasMoved = false
        lastTarget = nil
        let host = UIHostingController(rootView: ItemMovePreview(title: title, colorHex: colorHex, originalDate: date, state: dropState))
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        host.view.frame = frame(at: point, in: window)
        window.addSubview(host.view)
        preview = host
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        selection.prepare()
    }

    func update(to point: CGPoint) {
        guard let view = preview?.view, let window = view.window else { return }
        if hypot(point.x - startPoint.x, point.y - startPoint.y) > Self.minimumTravel {
            hasMoved = true
        }
        view.frame = frame(at: point, in: window)
        let target = dropState.hover(atWindowPoint: point)
        if target != lastTarget, target != nil {
            selection.selectionChanged()
        }
        lastTarget = target
    }

    /// 놓은 곳의 날짜. 거의 움직이지 않았거나, 달력 밖이거나, 원래 날이면 `nil`이다.
    func finish(at point: CGPoint) -> LocalDate? {
        var target = hasMoved ? dropState.day(atWindowPoint: point)?.day : nil
        if target == originalDate {
            target = nil
        }
        end()
        if target != nil {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        return target
    }

    /// 미리보기를 떼고 달력 강조를 지운다. 옮기는 중이 아니면 아무것도 하지 않는다("나중에" 끌기의 강조를 건드리지 않게).
    func end() {
        guard let preview else { return }
        preview.view.removeFromSuperview()
        self.preview = nil
        dropState.endHover()
    }

    /// 손가락 위(가리지 않게)에 놓고, 창 밖으로 나가지 않게 맞춘다.
    private func frame(at point: CGPoint, in window: UIWindow) -> CGRect {
        let size = Self.previewSize
        let bounds = window.bounds.inset(by: window.safeAreaInsets)
        let x = min(max(point.x - size.width / 2, bounds.minX + 8), bounds.maxX - size.width - 8)
        let y = max(point.y - size.height - 36, bounds.minY + 4)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

/// 손가락을 따라가는 일정 표시. 제목과 놓을 날짜를 보여준다.
struct ItemMovePreview: View {
    let title: String
    let colorHex: String
    let originalDate: LocalDate
    let state: CalendarDropState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: colorHex))
                    .frame(width: 4, height: 16)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            Text(targetText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }

    private var targetText: String {
        guard let target = state.target, target != originalDate else { return "옮길 날짜 위에서 놓으세요" }
        return "→ \(target.koreanMonthDayWeekdayText)"
    }
}
