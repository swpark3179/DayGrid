import DayGridCore
import SwiftData

enum AppModelContainer {
    static var schema: Schema {
        Schema([ItemCategory.self, Item.self])
    }

    /// 앱이 쓰는 저장소. iCloud 동기화는 Phase 9에서 켠다.
    /// UI 테스트(`-UITestSeedData`)에서는 매번 같은 상태로 시작하도록 메모리 전용 저장소에 샘플 데이터를 넣는다.
    @MainActor
    static func make(options: LaunchOptions) -> ModelContainer {
        let schema = Self.schema
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: options.seedSampleData,
            cloudKitDatabase: .none
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            try DefaultCategories.insertIfNeeded(into: container.mainContext)
            if options.seedSampleData {
                try SampleData.insert(into: container.mainContext, today: options.fixedToday ?? LocalDate.today())
            }
            return container
        } catch {
            fatalError("Could not create the model container: \(error)")
        }
    }
}
