import DayGridCore
import SwiftUI

/// 알림을 칩으로 켜고 끈다(일정 편집). 카테고리 칩(`CategoryChips`)과 모양은 같지만, 여러 개를 함께 켤 수 있다.
///
/// - 켠 칩은 강조 색으로 채우고 흰 글자로 쓴다. 칩이 화면보다 길면 가로로 스크롤한다.
/// - Form 행 안에 버튼이 여럿이므로 `.plain` 스타일로 둔다. 기본 스타일이면 행을 누를 때 버튼이 함께 눌린다.
/// - 알림 권한은 부르는 쪽이 `mask`가 늘 때 묻는다.
struct ReminderChips: View {
    let options: [ReminderOption]
    /// 켠 알림(`ReminderOption.bit`의 합)
    @Binding var mask: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    chip(option)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ option: ReminderOption) -> some View {
        let isOn = mask & option.bit != 0
        return Button {
            withAnimation(reduceMotion ? nil : .snappy) {
                mask ^= option.bit
            }
        } label: {
            Text(option.koreanText)
                .font(.subheadline.weight(isOn ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Capsule().fill(isOn ? Color.accentColor : Color.secondary.opacity(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.koreanText)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("reminder.\(option.koreanText)")
    }
}
