import Foundation

/// iCloud 동기화가 실패한 이유. 앱이 CloudKit 오류를 이 종류로 바꿔 넘긴다.
public enum CloudSyncFailure: Hashable, Sendable {
    /// iCloud에 로그인하지 않았거나 iCloud Drive가 꺼져 있다.
    case notSignedIn
    case quotaExceeded
    /// 네트워크가 없거나 서버가 바쁘다. 시스템이 나중에 다시 시도한다.
    case network
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

    public init(id: UUID, kind: Kind, startDate: Date, endDate: Date?, failure: CloudSyncFailure?) {
        self.id = id
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.failure = failure
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
        let failure: CloudSyncFailure
        let date: Date
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
            failures[event.kind] = Failure(failure: failure, date: endDate)
        } else {
            failures[event.kind] = nil
            lastSuccess = max(lastSuccess ?? endDate, endDate)
        }
    }

    public var status: Status {
        if let offReason {
            return .off(offReason)
        }
        if !inProgress.isEmpty {
            return .syncing
        }
        if let latest = failures.values.max(by: { $0.date < $1.date }) {
            return .failed(latest.failure, at: latest.date)
        }
        if let lastSuccess {
            return .upToDate(lastSync: lastSuccess)
        }
        return .waiting
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
