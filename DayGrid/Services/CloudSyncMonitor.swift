import CloudKit
import CoreData
import DayGridCore
import Foundation
import Observation
import SwiftData

/// iCloud 동기화 상태. SwiftData가 안에서 쓰는 `NSPersistentCloudKitContainer`의 이벤트 알림을 듣고,
/// Core `CloudSyncState`로 설정 화면에 보일 상태를 계산한다.
///
/// 다른 기기의 변경을 받으면(가져오기 성공) 중복을 합치고 알림을 다시 맞춘다.
/// `CKContainer`는 entitlements가 없으면 앱이 꺼지므로 직접 부르지 않고, 상태는 이벤트로만 판단한다.
@MainActor
@Observable
final class CloudSyncMonitor {
    static let shared = CloudSyncMonitor()

    private(set) var state = CloudSyncState()

    /// 앱이 만든 저장소. 가져온 뒤 중복을 합칠 때 쓴다.
    @ObservationIgnored var container: ModelContainer?
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    @ObservationIgnored private var pendingMerge: Task<Void, Never>?

    /// 저장소를 만들기 전에 부른다. 준비(setup) 이벤트는 저장소를 여는 중에 온다.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
            else { return }
            let converted = Self.convert(event)
            Task { @MainActor in
                CloudSyncMonitor.shared.apply(converted)
            }
        }
    }

    /// 동기화를 쓰지 않을 때(테스트 실행, iCloud 저장소를 열지 못함)
    func turnOff(_ reason: CloudSyncOffReason) {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        state = .off(reason)
    }

    private func apply(_ event: CloudSyncEvent) {
        state.apply(event)
        if event.kind == .download, event.endDate != nil, event.failure == nil {
            scheduleMerge()
        }
    }

    /// 가져온 변경이 메인 컨텍스트에 반영될 시간을 조금 두고, 여러 번 오면 한 번만 한다.
    private func scheduleMerge(after delay: Duration = .seconds(2)) {
        pendingMerge?.cancel()
        pendingMerge = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let context = container?.mainContext else { return }
            DuplicateMerger.mergeAll(in: context)
            NotificationScheduler.shared.scheduleSync(after: .zero)
            WidgetSnapshotWriter.shared.scheduleWrite(after: .zero)
        }
    }

    // MARK: - 이벤트 변환

    private nonisolated static func convert(_ event: NSPersistentCloudKitContainer.Event) -> CloudSyncEvent {
        let kind: CloudSyncEvent.Kind
        switch event.type {
        case .setup: kind = .setup
        case .import: kind = .download
        case .export: kind = .upload
        @unknown default: kind = .setup
        }
        let failure: CloudSyncFailure?
        if event.endDate != nil, !event.succeeded {
            failure = event.error.map(classify) ?? .other(message: "알 수 없는 오류")
        } else {
            failure = nil
        }
        return CloudSyncEvent(id: event.identifier, kind: kind, startDate: event.startDate, endDate: event.endDate, failure: failure)
    }

    /// CloudKit 오류를 종류로 나눈다. Core Data가 감싼 오류는 한 겹 벗겨서 본다.
    private nonisolated static func classify(_ error: any Error) -> CloudSyncFailure {
        let nsError = error as NSError
        // NSCloudKitMirroringDelegate가 iCloud 계정이 없을 때 쓰는 코드
        if nsError.domain == NSCocoaErrorDomain, nsError.code == 134_400 {
            return .notSignedIn
        }
        guard let ckError = (error as? CKError) ?? (nsError.userInfo[NSUnderlyingErrorKey] as? CKError) else {
            return .other(message: nsError.localizedDescription)
        }
        switch ckError.code {
        case .notAuthenticated:
            return .notSignedIn
        case .quotaExceeded:
            return .quotaExceeded
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return .network
        case .partialFailure:
            // 레코드별 오류(예: Production 스키마에 없는 필드) 중 첫 번째를 보여준다.
            if let first = ckError.partialErrorsByItemID?.values.first {
                return classify(first)
            }
            return .other(message: ckError.localizedDescription)
        default:
            return .other(message: ckError.localizedDescription)
        }
    }
}
