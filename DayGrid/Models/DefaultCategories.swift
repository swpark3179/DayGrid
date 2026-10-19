import Foundation
import SwiftData

/// 처음 실행할 때 넣는 기본 카테고리.
/// id를 고정해 두면 나중에 iCloud 동기화를 켰을 때 기기마다 만든 기본값을 같은 것으로 합칠 수 있다.
enum DefaultCategories {
    struct Seed: Sendable {
        let id: UUID
        let name: String
        let colorHex: String
    }

    static let seeds: [Seed] = [
        Seed(id: UUID(uuidString: "D4A9C0E1-1F2B-4C3D-8E00-000000000001")!, name: "개인", colorHex: "#4263EB"),
        Seed(id: UUID(uuidString: "D4A9C0E1-1F2B-4C3D-8E00-000000000002")!, name: "업무", colorHex: "#E8590C"),
        Seed(id: UUID(uuidString: "D4A9C0E1-1F2B-4C3D-8E00-000000000003")!, name: "가족", colorHex: "#2F9E44"),
        Seed(id: UUID(uuidString: "D4A9C0E1-1F2B-4C3D-8E00-000000000004")!, name: "건강", colorHex: "#E03131"),
        Seed(id: UUID(uuidString: "D4A9C0E1-1F2B-4C3D-8E00-000000000005")!, name: "기타", colorHex: "#495057"),
    ]

    /// 카테고리가 하나도 없을 때만 기본 카테고리를 넣는다.
    static func insertIfNeeded(into context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<ItemCategory>()) == 0 else { return }
        for (index, seed) in seeds.enumerated() {
            context.insert(ItemCategory(id: seed.id, name: seed.name, colorHex: seed.colorHex, sortOrder: index))
        }
        try context.save()
    }
}
