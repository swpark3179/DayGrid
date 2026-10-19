import Foundation
import SwiftData

/// 일정과 할일을 묶는 카테고리. 달력에서는 카테고리 색으로 그린다.
@Model
final class ItemCategory {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#4263EB"
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Item.category)
    var items: [Item]? = []

    init(id: UUID = UUID(), name: String, colorHex: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
    }
}
