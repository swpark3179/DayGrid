import DayGridCore
import Observation
import SwiftUI
import UIKit

/// 일정을 꾹 눌러 달력의 다른 날로 옮기는 동안의 미리보기와 놓을 날짜.
/// 하루 상세에서 옮기기(원래 날짜가 있음)와 "나중에"에서 달력에 넣기(원래 날짜 없음)가 함께 쓴다.
///
/// - 미리보기는 창 맨 위에 붙인다. 시트 안의 SwiftUI 뷰는 시트 밖에 그릴 수 없어서다.
/// - 손가락 아래 날짜는 `CalendarDropState.hover(atWindowPoint:)`가 찾고, 달력이 그 칸을 강조한다.
/// - 손가락을 거의 움직이지 않고 놓으면 옮기지 않는다(꾹 눌렀다 떼기만 해도 아래 날짜로 옮겨지지 않게).
/// - 미리보기는 들어 올리듯 나타나고, 놓으면 그 칸으로 줄어들며 사라진다. 취소하면 시작한 자리로 돌아가며 사라진다.
///   동작 줄이기(`UIAccessibility.isReduceMotionEnabled`)면 크기와 위치는 두고 투명도만 바꾼다.
/// - `showsCancelMark`면 화면 맨 위 가운데에 취소 표시(X)를 띄운다(하루 상세, 사용자 요청 2026-10-23).
///   손가락이 그 위에 오면 표시가 커지며 채워지고 미리보기는 작고 흐려진다. 거기서 놓으면 옮기지 않는다.
@MainActor
final class ItemMoveSession {
    /// 이만큼 넘게 움직여야 놓았을 때 옮긴다.
    static let minimumTravel: CGFloat = 16
    /// 미리보기 크기. 날짜 글자가 바뀌어도 크기가 그대로이도록 고정한다.
    static let previewSize = CGSize(width: 240, height: 56)
    /// 취소 표시를 그리는 뷰의 크기. 손가락이 들어오면 표시가 커지므로 그림자까지 여유를 둔다.
    static let cancelMarkSize = CGSize(width: 72, height: 72)

    private let dropState = CalendarDropState.shared
    private var preview: UIHostingController<ItemMovePreview>?
    private var cancelMark: UIHostingController<MoveCancelMark>?
    private var cancelState = MoveCancelState()
    /// 여기에서 놓으면 옮기지 않는다(창 좌표). 취소 표시가 없으면 `nil`
    private var cancelZone: CGRect?
    private var originalDate: LocalDate?
    private var startPoint = CGPoint.zero
    private var hasMoved = false
    private var lastTarget: LocalDate?
    private let selection = UISelectionFeedbackGenerator()

    func begin(title: String, colorHex: String, from date: LocalDate?, at point: CGPoint, in window: UIWindow, showsCancelMark: Bool = false) {
        end(animated: false)
        originalDate = date
        startPoint = point
        hasMoved = false
        lastTarget = nil
        cancelState = MoveCancelState()
        let host = UIHostingController(rootView: ItemMovePreview(
            title: title,
            colorHex: colorHex,
            originalDate: date,
            state: dropState,
            cancel: showsCancelMark ? cancelState : nil
        ))
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        host.view.frame = frame(at: point, in: window)
        window.addSubview(host.view)
        preview = host
        // 들어 올리기: 조금 작고 투명하게 시작해 제 크기로
        host.view.alpha = 0
        if !Self.reducesMotion {
            host.view.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            host.view.alpha = 1
            host.view.transform = .identity
        }
        if showsCancelMark {
            showCancelMark(in: window)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        selection.prepare()
    }

    func update(to point: CGPoint) {
        guard let view = preview?.view, let window = view.window else { return }
        if hypot(point.x - startPoint.x, point.y - startPoint.y) > Self.minimumTravel {
            hasMoved = true
        }
        // 미리보기는 취소 표시 위에서 작아지므로(transform) frame 대신 center로 옮긴다.
        let previewFrame = frame(at: point, in: window)
        view.center = CGPoint(x: previewFrame.midX, y: previewFrame.midY)
        let cancels = cancelZone?.contains(point) ?? false
        if cancels != cancelState.isTargeted {
            cancelState.isTargeted = cancels
            if cancels {
                dropState.endHover()
            }
            setPreviewDimmed(cancels)
            selection.selectionChanged()
        }
        let target = cancels ? nil : dropState.hover(atWindowPoint: point)
        if target != lastTarget, target != nil {
            selection.selectionChanged()
        }
        lastTarget = target
    }

    /// 놓은 곳의 날짜. 거의 움직이지 않았거나, 달력 밖이거나, 취소 표시 위이거나, 원래 날이면 `nil`이다.
    /// 날짜가 있으면 미리보기가 그 칸으로 빨려 들고, 없으면 시작한 자리로 돌아간다.
    func finish(at point: CGPoint) -> LocalDate? {
        let cancels = cancelZone?.contains(point) ?? false
        var target = hasMoved && !cancels ? dropState.day(atWindowPoint: point)?.day : nil
        if target == originalDate {
            target = nil
        }
        if let target, let cell = dropState.windowFrame(of: target) {
            end(animated: true, toward: CGPoint(x: cell.midX, y: cell.midY), scale: 0.3)
        } else {
            end(animated: true)
        }
        if target != nil {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        return target
    }

    /// 미리보기와 취소 표시를 떼고 달력 강조를 지운다. 옮기는 중이 아니면 아무것도 하지 않는다.
    /// `animated`면 `toward`(창 좌표, 없으면 시작한 자리)로 움직이며 사라진 뒤 뗀다.
    func end(animated: Bool = false, toward destination: CGPoint? = nil, scale: CGFloat = 0.85) {
        guard let preview else { return }
        self.preview = nil
        dropState.endHover()
        hideCancelMark(animated: animated)
        let view: UIView = preview.view
        guard animated, view.window != nil else {
            view.removeFromSuperview()
            return
        }
        let center = destination ?? CGPoint(x: startPoint.x, y: startPoint.y - Self.previewSize.height / 2 - 36)
        let reducesMotion = Self.reducesMotion
        UIView.animate(withDuration: reducesMotion ? 0.15 : 0.28, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            view.alpha = 0
            if !reducesMotion {
                view.center = center
                view.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
        } completion: { _ in
            view.removeFromSuperview()
        }
    }

    // MARK: - 취소 표시

    /// 취소 표시의 가운데(창 좌표). 화면 맨 위 가운데, 상태 막대(다이내믹 아일랜드) 바로 아래다.
    /// 달력 탭 머리 줄(왼쪽 연·월과 오른쪽 버튼 사이)의 빈 가운데와 같은 높이다.
    nonisolated static func cancelMarkCenter(in bounds: CGRect, safeAreaTop: CGFloat) -> CGPoint {
        CGPoint(x: bounds.midX, y: bounds.minY + safeAreaTop + 26)
    }

    /// 여기에서 놓으면 옮기지 않는다. 표시보다 넓게 잡고, 화면 맨 위 끝까지 넣는다.
    /// 아래쪽은 표시 바로 밑까지라 달력의 요일 줄과 날짜 칸에 걸치지 않는다.
    nonisolated static func cancelZone(in bounds: CGRect, safeAreaTop: CGFloat) -> CGRect {
        let center = cancelMarkCenter(in: bounds, safeAreaTop: safeAreaTop)
        return CGRect(x: center.x - 60, y: bounds.minY, width: 120, height: center.y - bounds.minY + 36)
    }

    /// 취소 표시를 띄운다. 미리보기보다 위에 붙여서, 미리보기가 맨 위로 올라와도 가리지 않는다.
    private func showCancelMark(in window: UIWindow) {
        let host = UIHostingController(rootView: MoveCancelMark(state: cancelState))
        // 뷰 위쪽이 상태 막대 영역에 조금 걸친다. 안전 영역만큼 표시가 밀려 내려가지 않게 한다.
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        host.view.bounds = CGRect(origin: .zero, size: Self.cancelMarkSize)
        host.view.center = Self.cancelMarkCenter(in: window.bounds, safeAreaTop: window.safeAreaInsets.top)
        window.addSubview(host.view)
        cancelMark = host
        cancelZone = Self.cancelZone(in: window.bounds, safeAreaTop: window.safeAreaInsets.top)
        // 시트가 내려가는 동안 위에서 톡 튀어나온다.
        host.view.alpha = 0
        if !Self.reducesMotion {
            host.view.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        }
        UIView.animate(withDuration: 0.35, delay: 0.08, usingSpringWithDamping: 0.65, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            host.view.alpha = 1
            host.view.transform = .identity
        }
    }

    private func hideCancelMark(animated: Bool) {
        cancelZone = nil
        guard let cancelMark else { return }
        self.cancelMark = nil
        let view: UIView = cancelMark.view
        guard animated, view.window != nil else {
            view.removeFromSuperview()
            return
        }
        let reducesMotion = Self.reducesMotion
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            view.alpha = 0
            if !reducesMotion {
                view.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            }
        } completion: { _ in
            view.removeFromSuperview()
        }
    }

    /// 취소 표시 위에서는 미리보기를 작고 흐리게 해서, 놓으면 버려진다는 것을 보인다.
    private func setPreviewDimmed(_ dimmed: Bool) {
        guard let view = preview?.view else { return }
        let reducesMotion = Self.reducesMotion
        UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            view.alpha = dimmed ? 0.55 : 1
            if !reducesMotion {
                view.transform = dimmed ? CGAffineTransform(scaleX: 0.85, y: 0.85) : .identity
            }
        }
    }

    private static var reducesMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// 손가락 위(가리지 않게)에 놓고, 창 밖으로 나가지 않게 맞춘다.
    private func frame(at point: CGPoint, in window: UIWindow) -> CGRect {
        let size = Self.previewSize
        let bounds = window.bounds.inset(by: window.safeAreaInsets)
        let x = min(max(point.x - size.width / 2, bounds.minX + 8), bounds.maxX - size.width - 8)
        let y = max(point.y - size.height - 36, bounds.minY + 4)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

/// 손가락이 취소 표시 위에 있는지. 표시와 미리보기가 함께 본다.
@MainActor
@Observable
final class MoveCancelState {
    var isTargeted = false
}

/// 손가락을 따라가는 일정 표시. 제목과 놓을 날짜를 보여준다.
struct ItemMovePreview: View {
    let title: String
    let colorHex: String
    /// 원래 날짜. "나중에" 항목이면 `nil`
    let originalDate: LocalDate?
    let state: CalendarDropState
    /// 취소 표시가 있으면 그 상태
    var cancel: MoveCancelState?

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
        if cancel?.isTargeted == true { return "놓으면 옮기지 않습니다" }
        guard let target = state.target, target != originalDate else { return "옮길 날짜 위에서 놓으세요" }
        return "→ \(target.koreanMonthDayWeekdayText)"
    }
}

/// 옮기는 동안 화면 맨 위 가운데에 뜨는 취소 표시(X). 손가락이 들어오면 커지며 채워진다.
/// 누르기를 받지 않는다(손가락은 꾹 누른 행의 제스처가 끝까지 잡고 있다).
struct MoveCancelMark: View {
    let state: MoveCancelState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isTargeted = state.isTargeted
        Image(systemName: "xmark")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(isTargeted ? Color(uiColor: .systemBackground) : Color.primary)
            .frame(width: 44, height: 44)
            .background {
                if isTargeted {
                    Circle().fill(Color.primary)
                } else {
                    Circle().fill(.regularMaterial)
                }
            }
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            .scaleEffect(isTargeted && !reduceMotion ? 1.2 : 1)
            .animation(.snappy, value: isTargeted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("옮기기 취소")
    }
}
