import Foundation
import OSLog

/// 이 앱 프로세스의 기록(os_log)에서 CloudKit·Core Data 줄을 읽는다.
///
/// 동기화 실패 이벤트의 오류에는 원인이 빠져 있을 수 있다(빌드 10: 안쪽 오류 없는 `partialFailure(2)`).
/// Core Data와 CloudKit은 같은 실패를 레코드별 오류까지 기록에 남기므로, 그 줄을 읽어 Core `CloudKitErrorReader`에 넘긴다.
/// Mac이 없어 기기 로그를 볼 수 없으므로 앱 안에서 읽는다. 읽는 데 시간이 걸릴 수 있어 메인 스레드 밖에서 부른다.
enum CloudSyncLogReader {
    /// 한 번에 훑는 기록 수의 한도. 시각으로 위치를 정하지 못하는 경우(처음부터 읽힘)에도 오래 걸리지 않게 한다.
    private static let maxScannedEntries = 50_000
    private static let maxLines = 200

    /// `from`...`to` 사이에 남은 CloudKit·Core Data 기록 줄(오래된 것부터). 읽지 못하면 빈 배열.
    static func lines(from start: Date, to end: Date) -> [String] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
              let entries = try? store.getEntries(at: store.position(date: start))
        else { return [] }
        var lines: [String] = []
        var scanned = 0
        for entry in entries {
            scanned += 1
            if scanned > maxScannedEntries || entry.date > end { break }
            guard entry.date >= start, let log = entry as? OSLogEntryLog, isCloudSync(log) else { continue }
            lines.append(log.composedMessage)
            if lines.count > maxLines {
                lines.removeFirst()
            }
        }
        return lines
    }

    /// Core Data(CoreData+CloudKit)와 CloudKit 기록인지
    private static func isCloudSync(_ log: OSLogEntryLog) -> Bool {
        let subsystem = log.subsystem.lowercased()
        if subsystem.contains("coredata") || subsystem.contains("cloudkit") {
            return true
        }
        let message = log.composedMessage
        return message.contains("CoreData+CloudKit") || message.contains("CKError")
    }
}
