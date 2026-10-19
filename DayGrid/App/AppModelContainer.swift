import DayGridCore
import Foundation
import SwiftData

enum AppModelContainer {
    /// iCloud 컨테이너. `DayGrid.entitlements`, `cloudkit/DayGrid.ckdb`, CloudKit 스키마 워크플로와 같은 값이다.
    static let cloudKitContainerID = "iCloud.io.github.swpark3179.DayGrid"

    /// 저장하는 모델. 바꾸면 `cloudkit/DayGrid.ckdb`도 바꿔야 한다(`CloudKitSchemaTests`가 검사한다).
    static var modelTypes: [any PersistentModel.Type] {
        [ItemCategory.self, Item.self, PersonalHoliday.self, Person.self, RecurringTask.self, RecurrenceCompletion.self]
    }

    static var schema: Schema {
        Schema(modelTypes)
    }

    /// 앱이 쓰는 저장소.
    /// - 보통 실행: iCloud 개인 DB와 동기화한다. 열지 못하면 앱이 꺼지지 않게 같은 파일을 이 기기에만 저장하는 방식으로 연다.
    /// - UI 테스트(`-UITestSeedData`): 매번 같은 상태로 시작하도록 메모리 전용 저장소에 샘플 데이터를 넣는다.
    /// - 단위 테스트 호스트: 동기화 없이 연다(테스트는 각자 메모리 저장소를 만든다).
    @MainActor
    static func make(options: LaunchOptions) -> ModelContainer {
        let schema = Self.schema
        do {
            let container: ModelContainer
            if options.usesCloudSync {
                container = try makeSynced(schema: schema)
            } else {
                CloudSyncMonitor.shared.turnOff(.testRun)
                let configuration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: options.seedSampleData,
                    cloudKitDatabase: .none
                )
                container = try ModelContainer(for: schema, configurations: [configuration])
            }
            try DefaultCategories.insertIfNeeded(into: container.mainContext)
            if options.seedSampleData {
                try SampleData.insert(into: container.mainContext, today: options.fixedToday ?? LocalDate.today())
            }
            DuplicateMerger.mergeAll(in: container.mainContext)
            CloudSyncMonitor.shared.container = container
            return container
        } catch {
            fatalError("Could not create the model container: \(error)")
        }
    }

    @MainActor
    private static func makeSynced(schema: Schema) throws -> ModelContainer {
        let synced = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudKitContainerID))
        StoreBackup.copyOnceBeforeSync(storeURL: synced.url)
        CloudSyncMonitor.shared.start()
        do {
            return try ModelContainer(for: schema, configurations: [synced])
        } catch {
            CloudSyncMonitor.shared.turnOff(.unavailable(message: error.localizedDescription))
            let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [local])
        }
    }
}

/// iCloud 동기화를 처음 켜기 전의 저장소 파일을 한 번만 복사해 둔다(`Application Support/Backups/pre-icloud`).
/// 동기화를 켠 뒤 문제가 생겨도 이 기기에 있던 데이터를 되살릴 수 있게 하는 안전장치다.
enum StoreBackup {
    static let doneKey = "storeBackup.preICloud.done"

    static func copyOnceBeforeSync(storeURL: URL, defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)
        guard fileManager.fileExists(atPath: storeURL.path) else { return }

        let folder = storeURL.deletingLastPathComponent()
            .appending(path: "Backups", directoryHint: .isDirectory)
            .appending(path: "pre-icloud", directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(filePath: storeURL.path + suffix)
                let target = folder.appending(path: source.lastPathComponent)
                if fileManager.fileExists(atPath: source.path), !fileManager.fileExists(atPath: target.path) {
                    try fileManager.copyItem(at: source, to: target)
                }
            }
        } catch {
            // 백업은 안전장치일 뿐이다. 실패해도 앱은 계속 연다.
        }
    }
}
