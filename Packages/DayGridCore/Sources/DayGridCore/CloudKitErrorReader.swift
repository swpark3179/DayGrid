import Foundation

/// iCloud 동기화 오류(`NSPersistentCloudKitContainer.Event.error`)를 펼쳐 읽고 `CloudSyncFailure`로 나눈다.
///
/// 오류는 여러 겹이다.
/// - 묶음 실패(`partialFailure`, 2)는 레코드·영역마다의 오류를 `CKPartialErrors`에 담는다. 바깥 문구는
///   "작업을 완료할 수 없습니다. (CKErrorDomain 오류 2.)"뿐이라 원인을 알 수 없다.
/// - Core Data는 원래 오류를 `NSUnderlyingError`에 넣어 감싼다.
/// - 같은 묶음의 다른 레코드는 `batchRequestFailed`(22)로 함께 실패한다. 원인이 아니다.
///
/// Core는 CloudKit을 import하지 않으므로 도메인, 코드, userInfo 키를 값으로 쓴다(CloudKit `CKError.Code`와 같은 번호).
public enum CloudKitErrorReader {
    public static let domain = "CKErrorDomain"
    /// `CKPartialErrorsByItemIDKey`
    static let partialErrorsKey = "CKPartialErrors"
    /// CloudKit 서버가 보낸 문구. 예: "Cannot create new type CD_Item in production schema"
    static let serverMessageKey = "ServerErrorDescription"
    static let ckDescriptionKey = "CKErrorDescription"
    /// `NSMultipleUnderlyingErrorsKey`, Core Data `NSDetailedErrorsKey`(검사 오류 여러 개)
    static let multipleErrorsKeys = ["NSMultipleUnderlyingErrorsKey", "NSDetailedErrors"]
    /// NSCloudKitMirroringDelegate가 iCloud 계정이 없을 때 쓰는 Core Data 오류 코드
    static let coreDataNotSignedInCode = 134_400

    private static let partialFailure = 2
    private static let batchRequestFailed = 22
    private static let maxDepth = 6

    /// `CKError.Code` 이름. 보고서와 오류 문구에 쓴다.
    static let codeNames: [Int: String] = [
        1: "internalError", 2: "partialFailure", 3: "networkUnavailable", 4: "networkFailure",
        5: "badContainer", 6: "serviceUnavailable", 7: "requestRateLimited", 8: "missingEntitlement",
        9: "notAuthenticated", 10: "permissionFailure", 11: "unknownItem", 12: "invalidArguments",
        13: "resultsTruncated", 14: "serverRecordChanged", 15: "serverRejectedRequest", 16: "assetFileNotFound",
        17: "assetFileModified", 18: "incompatibleVersion", 19: "constraintViolation", 20: "operationCancelled",
        21: "changeTokenExpired", 22: "batchRequestFailed", 23: "zoneBusy", 24: "badDatabase",
        25: "quotaExceeded", 26: "zoneNotFound", 27: "limitExceeded", 28: "userDeletedZone",
        29: "tooManyParticipants", 30: "alreadyShared", 31: "referenceViolation", 32: "managedAccountRestricted",
        33: "participantMayNeedVerification", 34: "serverResponseLost", 35: "assetNotAvailable",
        36: "accountTemporarilyUnavailable",
    ]

    // MARK: - 나누기

    public static func failure(for error: any Error) -> CloudSyncFailure {
        let errors = flatten(error as NSError).map(\.error)
        if errors.contains(where: { isCloudKit($0, 9) || ($0.domain == NSCocoaErrorDomain && $0.code == coreDataNotSignedInCode) }) {
            return .notSignedIn
        }
        if errors.contains(where: { isCloudKit($0, 25) }) {
            return .quotaExceeded
        }
        let found = causes(in: errors)
        if let schema = found.first(where: isSchemaProblem) {
            return .schemaMismatch(message: summary(of: schema))
        }
        // badContainer, missingEntitlement, permissionFailure("Invalid bundle ID for container" 등)
        if let setup = found.first(where: { isCloudKit($0, 5) || isCloudKit($0, 8) || isCloudKit($0, 10) }) {
            return .containerSetup(message: summary(of: setup))
        }
        if let first = found.first, first.domain == domain, networkCodes.contains(first.code) {
            return .network
        }
        return .other(message: summary(of: found.first ?? (error as NSError)))
    }

    /// 네트워크가 없거나 서버가 바쁘다. 시스템이 나중에 다시 시도한다.
    private static let networkCodes: Set<Int> = [3, 4, 6, 7, 23, 34]

    /// 원인 오류. CloudKit 오류 중 묶음(2)과 덩달아 실패(22)를 뺀다. 없으면 CloudKit이 아닌 맨 안쪽 오류.
    static func causes(in errors: [NSError]) -> [NSError] {
        let cloudKit = errors.filter { $0.domain == domain && $0.code != partialFailure && $0.code != batchRequestFailed }
        if !cloudKit.isEmpty {
            return cloudKit
        }
        return errors.filter { $0.domain != domain && children(of: $0).isEmpty }
    }

    /// Production 스키마에 레코드 타입·필드가 없거나 타입이 다르다.
    /// - "Cannot create new type CD_Item in production schema"
    /// - "Cannot create or modify field 'CD_x' in record type 'CD_Item' in production schema"
    /// - "invalid attempt to set value type STRING for field 'CD_x' for type 'CD_Item', defined to be: INT64"
    static func isSchemaProblem(_ error: NSError) -> Bool {
        guard error.domain == domain, [12, 15].contains(error.code), let message = serverMessage(of: error)?.lowercased() else {
            return false
        }
        return message.contains("schema") || message.contains("record type") || message.contains("invalid attempt to set value type")
    }

    // MARK: - 펼치기

    /// `error`와 안쪽 오류 전부(바깥 먼저). 레코드별 오류는 키 이름 순으로 늘어놓아 매번 같은 순서가 된다.
    static func flatten(_ error: NSError, depth: Int = 0) -> [(depth: Int, error: NSError)] {
        var result = [(depth: depth, error: error)]
        guard depth < maxDepth else { return result }
        for child in children(of: error) {
            result += flatten(child, depth: depth + 1)
        }
        return result
    }

    static func children(of error: NSError) -> [NSError] {
        var result: [NSError] = []
        if let partial = error.userInfo[partialErrorsKey] as? [AnyHashable: Any] {
            let sorted = partial.sorted { String(describing: $0.key) < String(describing: $1.key) }
            result += sorted.compactMap { ($0.value as? any Error).map { $0 as NSError } }
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? any Error {
            result.append(underlying as NSError)
        }
        for key in multipleErrorsKeys {
            if let multiple = error.userInfo[key] as? [Any] {
                result += multiple.compactMap { ($0 as? any Error).map { $0 as NSError } }
            }
        }
        return result
    }

    // MARK: - 문구

    static func isCloudKit(_ error: NSError, _ code: Int) -> Bool {
        error.domain == domain && error.code == code
    }

    static func serverMessage(of error: NSError) -> String? {
        nonEmpty(error.userInfo[serverMessageKey] as? String)
    }

    /// 오류에 실린 설명. 없으면 `nil`(시스템이 만드는 "작업을 완료할 수 없습니다" 문구는 쓰지 않는다).
    static func describedMessage(of error: NSError) -> String? {
        serverMessage(of: error)
            ?? nonEmpty(error.userInfo[NSLocalizedDescriptionKey] as? String)
            ?? nonEmpty(error.userInfo[ckDescriptionKey] as? String)
            ?? nonEmpty(error.userInfo["NSDebugDescription"] as? String)
    }

    /// "serverRejectedRequest(15): Cannot create new type CD_Item in production schema"
    static func summary(of error: NSError) -> String {
        let name = error.domain == domain ? "\(codeNames[error.code] ?? "CKError")(\(error.code))" : "\(error.domain) \(error.code)"
        guard let message = describedMessage(of: error) else { return name }
        return "\(name): \(message)"
    }

    /// 설정 화면에서 복사해 알려 줄 수 있는 설명. 오류마다 한 줄이고, 안쪽 오류는 들여 쓴다.
    /// 같은 내용(예: 레코드마다 똑같은 스키마 오류)은 한 번만 쓰고 개수를 붙인다.
    public static func report(of error: any Error) -> String {
        var lines: [(text: String, count: Int)] = []
        for (depth, nsError) in flatten(error as NSError) {
            let keys = nsError.userInfo.keys
                .filter { $0 != partialErrorsKey && $0 != NSUnderlyingErrorKey && !multipleErrorsKeys.contains($0) }
                .sorted()
            var text = String(repeating: "  ", count: depth) + summary(of: nsError)
            if !keys.isEmpty {
                text += " [\(keys.joined(separator: ", "))]"
            }
            if let index = lines.firstIndex(where: { $0.text == text }) {
                lines[index].count += 1
            } else {
                lines.append((text, 1))
            }
        }
        var text = lines.prefix(maxReportLines).map { $0.count > 1 ? "\($0.text) ×\($0.count)" : $0.text }
        if lines.count > maxReportLines {
            text.append("… 외 \(lines.count - maxReportLines)줄")
        }
        return text.joined(separator: "\n")
    }

    private static let maxReportLines = 40

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
