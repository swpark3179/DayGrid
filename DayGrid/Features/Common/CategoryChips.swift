import SwiftUI

/// 카테고리를 색 칩으로 고른다(일정 편집, 반복 할일 편집). 달력에서 색으로 구별하므로 고를 때도 색을 보여 준다.
///
/// - 고른 칩은 그 카테고리 색으로 채우고 흰 글자로 쓴다. 선택 표시는 칩 사이를 미끄러진다(`matchedGeometryEffect`).
/// - 맨 끝 "없음"은 카테고리 없음(`nil`)이다. 칩이 많으면 가로로 스크롤한다.
/// - Form 행 안에 버튼이 여럿이므로 `.plain` 스타일로 둔다. 기본 스타일이면 행을 누를 때 버튼이 함께 눌린다.
struct CategoryChips: View {
    let categories: [ItemCategory]
    @Binding var selection: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { category in
                    chip(id: category.id, name: category.name, colorHex: category.colorHex)
                }
                chip(id: nil, name: "없음", colorHex: CategoryPalette.uncategorizedHex)
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(id: UUID?, name: String, colorHex: String) -> some View {
        let isSelected = selection == id
        let color = Color(hex: colorHex)
        return Button {
            withAnimation(reduceMotion ? nil : .snappy) {
                selection = id
            }
        } label: {
            HStack(spacing: 6) {
                if id != nil {
                    Circle()
                        .fill(isSelected ? Color.white : color)
                        .frame(width: 8, height: 8)
                }
                Text(name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background {
                if isSelected {
                    Capsule()
                        .fill(color)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("category.\(name)")
    }
}
