import Foundation

/// iCloud 동기화가 실패한 이유. 앱이 CloudKit 오류를 이 종류로 바꿔 넘긴다.
public enum CloudSyncFailure: Hashable, Sendable {
    /// iCloud에 로그인하지 않았거나 iCloud Drive가 꺼져 있다.
    case notSignedIn
    case quotaExceeded
    /// 네트워크가 없거나 서버가 바쁘다. 시스템이 나중에 다시 시도한다.
    case network
    /// Production 스키마에 레코드 타입이나 필드가 없거나 타입이 다르다. CloudKit Console에서 배포해야 한다.
    case schemaMismatch(message: String)
    /// iCloud 컨테이너나 App ID 설정이 맞지 않는다(badContainer, missingEntitlement, permissionFailure).
    case containerSetup(message: String)
    /// 묶음 실패(partialFailure)인데 레코드별 원인이 오류에 들어 있지 않다(실기기 2026-10-21, 빌드 10).
    /// 그때 Production 스키마에는 DayGrid 레코드 타입이 하나도 없었다.
    case unexplainedPartialFailure
    /// 그 밖의 오류. 원인을 찾을 수 있게 메시지를 그대로 보여준다.
    case other(message: String)

    public var koreanText: String {
        switch self {
        case .notSignedIn:
            "iCloud에 로그인되어 있지 않습니다. 설정 앱에서 로그인하면 동기화됩니다."
        case .quotaExceeded:
            "iCloud 저장 공간이 부족합니다."
        case .network:
            "네트워크에 연결되지 않았습니다. 연결되면 다시 시도합니다."
        case .schemaMismatch(let message):
            "iCloud(Production)의 데이터 구조가 앱과 맞지 않습니다. CloudKit Console에서 스키마를 Production에 배포해야 합니다. (\(message))"
        case .containerSetup(let message):
            "iCloud 컨테이너 설정이 맞지 않습니다. App ID에 iCloud 컨테이너가 연결되어 있는지 확인해야 합니다. (\(message))"
        case .unexplainedPartialFailure:
            "iCloud가 이 기기의 변경을 받지 않았습니다(partialFailure). 오류에 자세한 원인이 없습니다. CloudKit Console에서 스키마를 Production에 배포했는지 먼저 확인해야 합니다. 오류 내용 복사에 앱 기록에서 찾은 내용이 함께 들어갑니다."
        case .other(let message):
            "동기화 오류: \(message)"
        }
    }
}

/// 동기화를 쓰지 않는 이유
public enum CloudSyncOffReason: Hashable, Sendable {
    /// UI 테스트나 단위 테스트 실행
    case testRun
    /// iCloud 저장소를 열지 못해 이 기기에만 저장한다.
    case unavailable(message: String)

    public var koreanText: String {
        switch self {
        case .testRun:
            "이 실행에서는 iCloud 동기화를 쓰지 않습니다."
        case .unavailable(let message):
            "iCloud 저장소를 열지 못해 이 기기에만 저장합니다. (\(message))"
        }
    }
}

/// 동기화 작업 하나(Core Data의 `NSPersistentCloudKitContainer.Event`를 옮긴 값).
public struct CloudSyncEvent: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// 저장소와 iCloud 연결 준비
        case setup
        /// iCloud에서 받기(다른 기기의 변경)
        case download
        /// iCloud로 보내기(이 기기의 변경)
        case upload
    }

    public let id: UUID
    public let kind: Kind
    public let startDate: Date
    /// 아직 진행 중이면 `nil`
    public let endDate: Date?
    /// 끝났는데 실패했으면 그 이유
    public let failure: CloudSyncFailure?
    /// 실패한 오류를 펼친 설명(`CloudKitErrorReader.report(of:)`). 설정 화면에서 복사해 알려 줄 수 있다.
    public let failureReport: String?

    public init(id: UUID, kind: Kind, startDate: Date, endDate: Date?, failure: CloudSyncFailure?, failureReport: String? = nil) {
        self.id = id
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.failure = failure
        self.failureReport = failureReport
    }
}

extension CloudSyncEvent.Kind {
    public var koreanName: String {
        switch self {
        case .setup: "준비"
        case .download: "받기"
        case .upload: "보내기"
        }
    }
}

/// 설정 화면에 보여줄 동기화 상태. 이벤트를 차례로 넣어 계산한다.
///
/// - 진행 중인 작업이 있으면 "동기화 중"이다.
/// - 종류(준비·받기·보내기)마다 마지막 결과를 기억한다. 실패한 종류가 하나라도 있으면 가장 최근 실패를 보여주고,
///   같은 종류가 다시 성공하면 그 실패를 지운다.
/// - 실패가 없으면 마지막으로 성공한 시각을 보여준다.
public struct CloudSyncState: Hashable, Sendable {
    public enum Status: Hashable, Sendable {
        case off(CloudSyncOffReason)
        /// 아직 끝난 작업이 없다.
        case waiting
        case syncing
        case upToDate(lastSync: Date)
        case failed(CloudSyncFailure, at: Date)
    }

    private struct Failure: Hashable, Sendable {
        var failure: CloudSyncFailure
        let date: Date
        let kind: CloudSyncEvent.Kind
        let report: String?
        let eventID: UUID
        /// 앱 기록에서 찾은 줄(`attachLog`)
        var logLines: [String] = []
    }

    public private(set) var offReason: CloudSyncOffReason?
    public private(set) var lastSuccess: Date?
    private var inProgress: Set<UUID> = []
    private var failures: [CloudSyncEvent.Kind: Failure] = [:]

    public init() {}

    public static func off(_ reason: CloudSyncOffReason) -> CloudSyncState {
        var state = CloudSyncState()
        state.offReason = reason
        return state
    }

    public mutating func apply(_ event: CloudSyncEvent) {
        guard let endDate = event.endDate else {
            inProgress.insert(event.id)
            return
        }
        inProgress.remove(event.id)
        if let failure = event.failure {
            failures[event.kind] = Failure(failure: failure, date: endDate, kind: event.kind, report: event.failureReport, eventID: event.id)
        } else {
            failures[event.kind] = nil
            lastSuccess = max(lastSuccess ?? endDate, endDate)
        }
    }

    /// 실패한 작업(`eventID`)에 앱 기록에서 찾은 줄을 붙인다. 기록으로 원인을 알아냈으면(`failure`) 원인을 알 수 없던
    /// 실패(`unexplainedPartialFailure`, `other`)를 그것으로 바꾼다. 그 사이 같은 종류의 작업이 다시 끝났으면 아무것도 하지 않는다.
    public mutating func attachLog(_ lines: [String], failure: CloudSyncFailure?, toEvent eventID: UUID) {
        guard let kind = failures.first(where: { $0.value.eventID == eventID })?.key, var current = failures[kind] else { return }
        current.logLines = lines
        if let failure {
            switch current.failure {
            case .unexplainedPartialFailure, .other:
                current.failure = failure
            case .notSignedIn, .quotaExceeded, .network, .schemaMismatch, .containerSetup:
                break
            }
        }
        failures[kind] = current
    }

    public var status: Status {
        if let offReason {
            return .off(offReason)
        }
        if !inProgress.isEmpty {
            return .syncing
        }
        if let latest = latestFailure {
            return .failed(latest.failure, at: latest.date)
        }
        if let lastSuccess {
            return .upToDate(lastSync: lastSuccess)
        }
        return .waiting
    }

    private var latestFailure: Failure? {
        guard offReason == nil else { return nil }
        return failures.values.max { $0.date < $1.date }
    }

    /// 보여주는 실패의 자세한 내용(복사용). 실패를 보여주지 않으면(동기화 중 포함) `nil`.
    /// 첫 줄은 작업 종류와 시각(UTC), 그 아래는 펼친 오류, 맨 아래는 앱 기록에서 찾은 줄이다.
    public var failureReport: String? {
        guard case .failed = status, let latest = latestFailure else { return nil }
        var lines = ["iCloud \(latest.kind.koreanName) 실패 \(latest.date.formatted(.iso8601))"]
        if let report = latest.report {
            lines.append(report)
        }
        if !latest.logLines.isEmpty {
            lines.append("앱 기록:")
            lines += latest.logLines.map { "  \($0)" }
        }
        return lines.joined(separator: "\n")
    }

    /// 한 줄 요약. "동기화 중", "최근 동기화: 5분 전" 등
    public func koreanSummary(now: Date) -> String {
        switch status {
        case .off:
            "꺼짐"
        case .waiting:
            "iCloud 연결 준비 중"
        case .syncing:
            "동기화 중"
        case .upToDate(let lastSync):
            "최근 동기화: \(Self.relativeText(from: lastSync, to: now))"
        case .failed:
            "동기화 문제"
        }
    }

    /// 요약 아래에 붙일 설명(꺼진 이유, 오류). 없으면 `nil`.
    public var koreanDetail: String? {
        switch status {
        case .off(let reason):
            reason.koreanText
        case .failed(let failure, _):
            failure.koreanText
        case .waiting, .syncing, .upToDate:
            nil
        }
    }

    /// "방금", "5분 전", "3시간 전", "2일 전"
    public static func relativeText(from date: Date, to now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60:
            return "방금"
        case ..<3600:
            return "\(Int(seconds / 60))분 전"
        case ..<86_400:
            return "\(Int(seconds / 3600))시간 전"
        default:
            return "\(Int(seconds / 86_400))일 전"
        }
    }
}
