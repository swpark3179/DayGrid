import SwiftData
import SwiftUI

/// 설정 → 카테고리. 순서 변경, 추가, 편집, 삭제.
struct CategoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ItemCategory.sortOrder) private var categories: [ItemCategory]

    @State private var editingCategory: ItemCategory?
    @State private var isAddingCategory = false
    @State private var categoryPendingDeletion: ItemCategory?

    var body: some View {
        List {
            Section {
                ForEach(categories) { category in
                    Button {
                        editingCategory = category
                    } label: {
                        CategoryRow(category: category)
                    }
                    .swipeActions {
                        // role: .destructive를 주면 확인 전에 행이 먼저 사라지므로 색만 빨갛게 한다.
                        Button("삭제") {
                            categoryPendingDeletion = category
                        }
                        .tint(.red)
                    }
                }
                .onMove(perform: move)
            } footer: {
                Text("카테고리를 지우면 그 카테고리의 일정은 '카테고리 없음'으로 바뀝니다.")
            }
        }
        .navigationTitle("카테고리")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("추가", systemImage: "plus") {
                    isAddingCategory = true
                }
            }
        }
        .sheet(item: $editingCategory) { category in
            CategoryEditView(category: category)
        }
        .sheet(isPresented: $isAddingCategory) {
            CategoryEditView(category: nil)
        }
        .confirmationDialog(
            "카테고리를 삭제할까요?",
            isPresented: isConfirmingDeletion,
            titleVisibility: .visible,
            presenting: categoryPendingDeletion
        ) { category in
            Button("'\(category.name)' 삭제", role: .destructive) {
                modelContext.delete(category)
                categoryPendingDeletion = nil
            }
        } message: { category in
            Text("이 카테고리의 일정 \(category.items?.count ?? 0)개는 '카테고리 없음'으로 바뀝니다.")
        }
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(
            get: { categoryPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    categoryPendingDeletion = nil
                }
            }
        )
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = categories
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in reordered.enumerated() {
            category.sortOrder = index
        }
    }
}

private struct CategoryRow: View {
    let category: ItemCategory

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: category.colorHex))
                .frame(width: 14, height: 14)
            Text(category.name)
                .foregroundStyle(.primary)
            Spacer()
            Text("\(category.items?.count ?? 0)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
