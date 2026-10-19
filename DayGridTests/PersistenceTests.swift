import DayGridCore
import Foundation
import SwiftData
import Testing
@testable import DayGrid

/// 앱을 껐다 켜는 상황을 흉내 낸다. 같은 파일로 저장소를 다시 열어 추가·수정·삭제가 남는지 본다.
@MainActor
struct PersistenceTests {
    let storeURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("DayGridTests-\(UUID().uuidString).store")

    private func openStore() throws -> ModelContainer {
        let schema = AppModelContainer.schema
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func removeStoreFiles() {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
    }

    @Test func createUpdateAndDeleteSurviveReopening() throws {
        defer { removeStoreFiles() }
        let day = LocalDate(year: 2026, month: 10, day: 21)!

        do {
            let store = try openStore()
            let item = Item(title: "저장 확인")
            store.mainContext.insert(item)
            item.scheduleAllDay(from: day, through: day)
            try store.mainContext.save()
        }

        do {
            let store = try openStore()
            let item = try #require(try store.mainContext.fetch(FetchDescriptor<Item>()).first)
            #expect(item.title == "저장 확인")
            #expect(item.startDay == day)
            item.title = "수정됨"
            try store.mainContext.save()
        }

        do {
            let store = try openStore()
            let items = try store.mainContext.fetch(FetchDescriptor<Item>())
            #expect(items.map(\.title) == ["수정됨"])
            let item = try #require(items.first)
            store.mainContext.delete(item)
            try store.mainContext.save()
        }

        do {
            let store = try openStore()
            #expect(try store.mainContext.fetchCount(FetchDescriptor<Item>()) == 0)
        }
    }
}
