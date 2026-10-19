import SwiftData
import SwiftUI

/// 카테고리 이름과 색을 정한다. `category`가 `nil`이면 새로 만든다.
struct CategoryEditView: View {
    let category: ItemCategory?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String
    @State private var colorHex: String

    init(category: ItemCategory?) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _colorHex = State(initialValue: category?.colorHex ?? CategoryPalette.swatches[0].hex)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("이름") {
                    TextField("카테고리 이름", text: $name)
                }
                Section("색상") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                        ForEach(CategoryPalette.swatches) { swatch in
                            swatchButton(swatch)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(category == nil ? "새 카테고리" : "카테고리 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func swatchButton(_ swatch: CategoryPalette.Swatch) -> some View {
        let isSelected = swatch.hex == colorHex
        return Button {
            colorHex = swatch.hex
        } label: {
            Circle()
                .fill(Color(hex: swatch.hex))
                .frame(width: 36, height: 36)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(swatch.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        if let category {
            category.name = trimmedName
            category.colorHex = colorHex
        } else {
            let existing = (try? modelContext.fetch(FetchDescriptor<ItemCategory>())) ?? []
            let nextOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
            modelContext.insert(ItemCategory(name: trimmedName, colorHex: colorHex, sortOrder: nextOrder))
        }
        dismiss()
    }
}
