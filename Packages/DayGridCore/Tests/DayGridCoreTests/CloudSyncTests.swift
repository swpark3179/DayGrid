import Foundation
import Testing
@testable import DayGridCore

private let start = Date(timeIntervalSince1970: 1_792_400_000)

private func uuid(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
}

private func event(
    _ number: Int,
    _ kind: CloudSyncEvent.Kind,
    at seconds: TimeInterval,
    ended: Bool = true,
    failure: CloudSyncFailure? = nil
) -> CloudSyncEvent {
    CloudSyncEvent(
        id: uuid(number),
        kind: kind,
        startDate: start.addingTimeInterval(seconds - 1),
        endDate: ended ? start.addingTimeInterval(seconds) : nil,
        failure: failure
    )
}

struct CloudSyncStateTests {
    @Test func startsWaitingAndShowsProgress() {
        var state = CloudSyncState()
        #expect(state.status == .waiting)
        #expect(state.koreanSummary(now: start) == "iCloud 연결 준비 중")

        state.apply(event(1, .setup, at: 0, ended: false))
        #expect(state.status == .syncing)
        state.apply(event(1, .setup, at: 2))
        #expect(state.status == .upToDate(lastSync: start.addingTimeInterval(2)))
        #expect(state.koreanDetail == nil)
    }

    @Test func staysSyncingUntilEveryRunningEventEnds() {
        var state = CloudSyncState()
        state.apply(event(1, .download, at: 0, ended: false))
        state.apply(event(2, .upload, at: 0, ended: false))
        state.apply(event(1, .download, at: 5))
        #expect(state.status == .syncing)
        state.apply(event(2, .upload, at: 9))
        #expect(state.status == .upToDate(lastSync: start.addingTimeInterval(9)))
    }

    @Test func aFailureStaysUntilTheSameKindSucceeds() {
        var state = CloudSyncState()
        state.apply(event(1, .download, at: 10))
        state.apply(event(2, .upload, at: 20, failure: .quotaExceeded))
        #expect(state.status == .failed(.quotaExceeded, at: start.addingTimeInterval(20)))

        // 받기가 성공해도 보내기 실패는 남는다
        state.apply(event(3, .download, at: 30))
        #expect(state.status == .failed(.quotaExceeded, at: start.addingTimeInterval(20)))
        #expect(state.lastSuccess == start.addingTimeInterval(30))
        #expect(state.koreanDetail == "iCloud 저장 공간이 부족합니다.")

        state.apply(event(4, .upload, at: 40))
        #expect(state.status == .upToDate(lastSync: start.addingTimeInterval(40)))
    }

    @Test func showsTheLatestFailure() {
        var state = CloudSyncState()
        state.apply(event(1, .setup, at: 10, failure: .notSignedIn))
        state.apply(event(2, .upload, at: 20, failure: .other(message: "Cannot create field")))
        #expect(state.status == .failed(.other(message: "Cannot create field"), at: start.addingTimeInterval(20)))
        #expect(state.koreanSummary(now: start) == "동기화 문제")
        #expect(state.koreanDetail == "동기화 오류: Cannot create field")
    }

    @Test func offIgnoresEvents() {
        var state = CloudSyncState.off(.testRun)
        state.apply(event(1, .setup, at: 1))
        #expect(state.status == .off(.testRun))
        #expect(state.koreanSummary(now: start) == "꺼짐")
        #expect(state.koreanDetail == "이 실행에서는 iCloud 동기화를 쓰지 않습니다.")
        #expect(CloudSyncState.off(.unavailable(message: "x")).koreanDetail == "iCloud 저장소를 열지 못해 이 기기에만 저장합니다. (x)")
    }

    @Test func relativeTimes() {
        #expect(CloudSyncState.relativeText(from: start, to: start.addingTimeInterval(30)) == "방금")
        #expect(CloudSyncState.relativeText(from: start, to: start.addingTimeInterval(5 * 60 + 10)) == "5분 전")
        #expect(CloudSyncState.relativeText(from: start, to: start.addingTimeInterval(3 * 3600)) == "3시간 전")
        #expect(CloudSyncState.relativeText(from: start, to: start.addingTimeInterval(2 * 86_400 + 5)) == "2일 전")
        // 시계가 조금 어긋나 미래 시각이 와도 "방금"
        #expect(CloudSyncState.relativeText(from: start.addingTimeInterval(10), to: start) == "방금")

        var state = CloudSyncState()
        state.apply(event(1, .download, at: 0))
        #expect(state.koreanSummary(now: start.addingTimeInterval(120)) == "최근 동기화: 2분 전")
    }
}

struct CloudKitSchemaFileTests {
    private let category = CloudKitSchemaFile.Entity(
        name: "ItemCategory",
        attributes: [
            .init(name: "name", kind: .string),
            .init(name: "id", kind: .uuid),
            .init(name: "sortOrder", kind: .integer),
            .init(name: "createdAt", kind: .date),
        ],
        toOneRelationships: []
    )

    @Test func mapsAttributesTheWayCoreDataDoes() {
        let entity = CloudKitSchemaFile.Entity(
            name: "Item",
            attributes: [
                .init(name: "title", kind: .string),
                .init(name: "isTask", kind: .boolean),
                .init(name: "inboxOrder", kind: .double),
                .init(name: "startDate", kind: .date),
                .init(name: "id", kind: .uuid),
                .init(name: "photo", kind: .binary),
            ],
            toOneRelationships: ["category"]
        )
        #expect(CloudKitSchemaFile.recordTypeName(of: entity) == "CD_Item")
        let fields = CloudKitSchemaFile.fields(of: entity).map { "\($0.name) \($0.type)" }
        #expect(fields == [
            "CD_category STRING",
            "CD_entityName STRING",
            "CD_id STRING",
            "CD_inboxOrder DOUBLE",
            "CD_isTask INT64",
            "CD_moveReceipt BYTES",
            "CD_moveReceipt_ckAsset ASSET",
            "CD_photo BYTES",
            "CD_photo_ckAsset ASSET",
            "CD_startDate TIMESTAMP",
            "CD_title STRING",
            "CD_title_ckAsset ASSET",
        ])
    }

    @Test func rendersSchemaLanguage() {
        let completion = CloudKitSchemaFile.Entity(
            name: "RecurrenceCompletion",
            attributes: [.init(name: "cycleStartKey", kind: .integer)],
            toOneRelationships: ["task"]
        )
        let text = CloudKitSchemaFile.render([completion, category])
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.contains("DEFINE SCHEMA"))
        #expect(text.hasSuffix(");\n"))

        // 레코드 타입은 이름 순, Users는 맨 뒤
        let recordTypes = lines.filter { $0.contains("RECORD TYPE") }.map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(recordTypes == ["RECORD TYPE CD_ItemCategory (", "RECORD TYPE CD_RecurrenceCompletion (", "RECORD TYPE Users ("])

        let block = Array(lines.drop { !$0.contains("CD_RecurrenceCompletion") }.prefix { !$0.contains(");") })
            .map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(block == [
            "RECORD TYPE CD_RecurrenceCompletion (",
            "\"___createTime\" TIMESTAMP,",
            "\"___createdBy\" REFERENCE,",
            "\"___etag\" STRING,",
            "\"___modTime\" TIMESTAMP,",
            "\"___modifiedBy\" REFERENCE,",
            "\"___recordID\" REFERENCE QUERYABLE,",
            "CD_cycleStartKey INT64,",
            "CD_entityName STRING,",
            "CD_moveReceipt BYTES,",
            "CD_moveReceipt_ckAsset ASSET,",
            "CD_task STRING,",
            "GRANT WRITE TO \"_creator\",",
            "GRANT CREATE TO \"_icloud\",",
            "GRANT READ TO \"_world\"",
        ])
    }

    @Test func renderingIsStableRegardlessOfInputOrder() {
        let completion = CloudKitSchemaFile.Entity(name: "RecurrenceCompletion", attributes: [], toOneRelationships: ["task"])
        #expect(CloudKitSchemaFile.render([completion, category]) == CloudKitSchemaFile.render([category, completion]))
    }
}

private func cloudKitError(_ code: Int, server: String? = nil, _ userInfo: [String: Any] = [:]) -> NSError {
    var info = userInfo
    if let server {
        info["ServerErrorDescription"] = server
    }
    return NSError(domain: "CKErrorDomain", code: code, userInfo: info)
}

/// 레코드마다의 오류를 담은 묶음 실패(partialFailure). 바깥에는 설명이 없다.
private func partialFailure(_ errors: [String: NSError]) -> NSError {
    NSError(domain: "CKErrorDomain", code: 2, userInfo: ["CKPartialErrors": errors])
}

struct CloudKitErrorReaderTests {
    private let schemaMessage = "Cannot create new type CD_Item in production schema"

    @Test func findsTheSchemaErrorInsideAPartialFailure() {
        let internalError = NSError(domain: "CKInternalErrorDomain", code: 2000)
        let error = partialFailure([
            "record-a": cloudKitError(22),
            "record-b": cloudKitError(15, server: schemaMessage, [NSUnderlyingErrorKey: internalError]),
            "record-c": cloudKitError(22),
        ])
        let failure = CloudKitErrorReader.failure(for: error)
        #expect(failure == .schemaMismatch(message: "serverRejectedRequest(15): \(schemaMessage)"))
        #expect(failure.koreanText.contains("CloudKit Console에서 스키마를 Production에 배포"))
        #expect(failure.koreanText.contains(schemaMessage))
    }

    @Test func readsThroughTheCoreDataWrapper() {
        let fieldMessage = "invalid attempt to set value type STRING for field 'CD_title' for type 'CD_Item', defined to be: INT64"
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134_419, userInfo: [
            NSUnderlyingErrorKey: partialFailure(["record-a": cloudKitError(12, server: fieldMessage)]),
        ])
        #expect(CloudKitErrorReader.failure(for: wrapped) == .schemaMismatch(message: "invalidArguments(12): \(fieldMessage)"))
    }

    @Test func classifiesAccountQuotaNetworkAndContainerProblems() {
        let notSignedIn = NSError(domain: NSCocoaErrorDomain, code: 134_400)
        #expect(CloudKitErrorReader.failure(for: notSignedIn) == .notSignedIn)
        #expect(CloudKitErrorReader.failure(for: partialFailure(["zone": cloudKitError(9)])) == .notSignedIn)
        #expect(CloudKitErrorReader.failure(for: partialFailure(["a": cloudKitError(25), "b": cloudKitError(22)])) == .quotaExceeded)
        #expect(CloudKitErrorReader.failure(for: cloudKitError(3)) == .network)
        #expect(CloudKitErrorReader.failure(for: partialFailure(["a": cloudKitError(7)])) == .network)

        let zone = partialFailure(["com.apple.coredata.cloudkit.zone": cloudKitError(10, server: "Invalid bundle ID for container")])
        #expect(CloudKitErrorReader.failure(for: zone) == .containerSetup(message: "permissionFailure(10): Invalid bundle ID for container"))
        #expect(CloudKitErrorReader.failure(for: cloudKitError(8)) == .containerSetup(message: "missingEntitlement(8)"))
    }

    /// 실기기에서 본 "작업을 완료할 수 없습니다. (CKErrorDomain 오류 2.)": 안쪽 오류가 없으면 적어도 이름과 키를 보여준다.
    @Test func aBarePartialFailureStillNamesItself() {
        let bare = NSError(domain: "CKErrorDomain", code: 2, userInfo: ["ContainerID": "iCloud.io.github.swpark3179.DayGrid"])
        #expect(CloudKitErrorReader.failure(for: bare) == .other(message: "partialFailure(2)"))
        #expect(CloudKitErrorReader.failure(for: bare).koreanText == "동기화 오류: partialFailure(2)")
        #expect(CloudKitErrorReader.report(of: bare) == "partialFailure(2) [ContainerID]")
    }

    @Test func usesTheDescriptionOfOtherErrors() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 134_060, userInfo: [NSLocalizedDescriptionKey: "A Core Data error occurred."])
        #expect(CloudKitErrorReader.failure(for: error) == .other(message: "NSCocoaErrorDomain 134060: A Core Data error occurred."))
        #expect(CloudKitErrorReader.failure(for: cloudKitError(26, [NSLocalizedDescriptionKey: "Zone does not exist"]))
            == .other(message: "zoneNotFound(26): Zone does not exist"))
    }

    @Test func reportIndentsInnerErrorsAndCountsRepeats() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 134_419, userInfo: [
            NSUnderlyingErrorKey: partialFailure([
                "record-a": cloudKitError(15, server: schemaMessage),
                "record-b": cloudKitError(15, server: schemaMessage),
                "record-c": cloudKitError(22),
            ]),
        ])
        let report = CloudKitErrorReader.report(of: error)
        #expect(report == """
            NSCocoaErrorDomain 134419
              partialFailure(2)
                serverRejectedRequest(15): \(schemaMessage) [ServerErrorDescription] ×2
                batchRequestFailed(22)
            """)
    }

    @Test func stateKeepsTheReportOfTheShownFailure() {
        var state = CloudSyncState()
        #expect(state.failureReport == nil)
        state.apply(CloudSyncEvent(
            id: uuid(1), kind: .upload, startDate: start, endDate: start.addingTimeInterval(5),
            failure: .other(message: "partialFailure(2)"), failureReport: "partialFailure(2)"
        ))
        #expect(state.failureReport == "iCloud 보내기 실패 2026-10-19T08:53:25Z\npartialFailure(2)")

        // 동기화 중에는 실패를 보여주지 않으므로 복사할 내용도 없다
        state.apply(event(2, .upload, at: 10, ended: false))
        #expect(state.failureReport == nil)
        state.apply(event(2, .upload, at: 10))
        #expect(state.failureReport == nil)
        #expect(CloudSyncState.off(.testRun).failureReport == nil)
    }
}
