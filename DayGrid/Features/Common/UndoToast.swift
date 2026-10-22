import Observation
import SwiftUI
import UIKit

/// 밀어서 지우기처럼 확인 없이 바로 저장하는 동작 뒤에 잠깐 띄우는 "실행 취소" 토스트의 상태.
/// 화면마다 `@State`로 두고, 그 화면 아래쪽에 `UndoToastView`를 얹는다(`undoToast(_:hidden:)`).
///
/// - 4초 뒤 내려간다. VoiceOver를 쓰는 중이면 버튼까지 갈 시간을 주려고 8초를 둔다.
///   UI 테스트에서는 20초를 둔다(`LaunchOptions.keepsToastsLonger`).
/// - 새로 띄우면 앞의 토스트를 바꾼다(앞의 되돌리기는 할 수 없게 된다).
/// - 시트 안에서 띄운 토스트는 시트와 함께 사라진다. 달력 칸을 가리지 않게 하려는 것이다.
@MainActor
@Observable
final class UndoToastState {
    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let systemImage: String
        let undo: @MainActor () -> Void
    }

    static let duration: TimeInterval = 4
    static let voiceOverDuration: TimeInterval = 8
    static let uiTestDuration: TimeInterval = 20
    /// 앱이 시작할 때 `LaunchOptions.keepsToastsLonger`로 정한다.
    static var usesUITestDuration = false

    private(set) var toast: Toast?

    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    func show(_ message: String, systemImage: String, undo: @escaping @MainActor () -> Void) {
        let duration = Self.usesUITestDuration
            ? Self.uiTestDuration
            : (UIAccessibility.isVoiceOverRunning ? Self.voiceOverDuration : Self.duration)
        let toast = Toast(message: message, systemImage: systemImage, undo: undo)
        withAnimation(.snappy) {
            self.toast = toast
        }
        UIAccessibility.post(notification: .announcement, argument: "\(message). 실행 취소할 수 있습니다.")
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self, self.toast?.id == toast.id else { return }
            self.dismiss()
        }
    }

    func undo() {
        guard let toast else { return }
        toast.undo()
        dismiss()
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.snappy) {
            toast = nil
        }
    }
}

/// 아래쪽에 뜨는 토스트. 문구와 "실행 취소" 버튼.
///
/// 남은 시간 막대는 두지 않는다. 몇 초씩 이어지는 애니메이션이 있으면 XCUITest가 앱이 멈추기를 기다리느라
/// 토스트가 내려간 뒤에야 버튼을 누르게 된다(PR #24 CI: `MotionTests`에서 "toast.undo"를 찾지 못함).
struct UndoToastView: View {
    let toast: UndoToastState.Toast
    let onUndo: () -> Void

    @State private var undoCount = 0

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.systemImage)
                .font(.body.weight(.medium))
                .accessibilityHidden(true)
            Text(toast.message)
                .font(.subheadline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("실행 취소") {
                undoCount += 1
                onUndo()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(red: 0.42, green: 0.71, blue: 1))
            .frame(minHeight: 44)
            .accessibilityIdentifier("toast.undo")
        }
        .foregroundStyle(.white)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .background(Color(white: 0.11).opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
        // 다크 모드에서 배경과 섞이지 않게 옅은 테두리
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .sensoryFeedback(.impact(weight: .light), trigger: undoCount)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toast")
    }
}

extension View {
    /// 화면 아래쪽에 `state`의 토스트를 얹는다. `hidden`이면(꾹 눌러 옮기는 중) 보이지 않는다.
    func undoToast(_ state: UndoToastState, hidden: Bool = false) -> some View {
        modifier(UndoToastHost(state: state, hidden: hidden))
    }
}

/// 토스트는 아래에서 올라오고 내려간다. 동작 줄이기면 나타나고 사라지기만 한다.
private struct UndoToastHost: ViewModifier {
    let state: UndoToastState
    let hidden: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast = state.toast, !hidden {
                UndoToastView(toast: toast) { state.undo() }
                    .id(toast.id)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
