import DayGridCore
import Foundation
import Observation

/// 공휴일 계산과 보정 자료(선거일, 임시공휴일)를 맡는다.
///
/// 보정 자료는 앱에 넣은 `KR-overrides.json`을 기본으로 쓴다.
/// 하루에 한 번까지 저장소(main 브랜치)의 같은 파일을 받아 와서, `version`이 더 높으면 저장해 두고 쓴다.
@MainActor
@Observable
final class HolidayService {
    static let remoteURL = URL(string: "https://raw.githubusercontent.com/swpark3179/DayGrid/main/DayGrid/Resources/holidays/KR-overrides.json")!

    private(set) var overrides: HolidayOverrides
    @ObservationIgnored private var cache: [Int: [Holiday]] = [:]
    private let allowsRemoteUpdate: Bool
    private let defaults: UserDefaults

    private enum Keys {
        static let lastCheck = "holidayOverrides.lastCheck"
        static let etag = "holidayOverrides.etag"
    }

    /// UI 테스트에서는 `allowsRemoteUpdate`를 꺼서 앱에 넣은 자료만 쓴다.
    init(allowsRemoteUpdate: Bool, bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        self.allowsRemoteUpdate = allowsRemoteUpdate
        self.defaults = defaults
        let bundled = Self.load(from: bundle.url(forResource: "KR-overrides", withExtension: "json"))
        let saved = allowsRemoteUpdate ? Self.load(from: Self.savedURL) : nil
        overrides = [bundled, saved].compactMap { $0 }.max { $0.version < $1.version } ?? .empty
    }

    /// `range` 안의 공휴일(날짜순).
    func holidays(in range: ClosedRange<LocalDate>) -> [Holiday] {
        (range.lowerBound.year...range.upperBound.year)
            .flatMap { holidays(inYear: $0) }
            .filter { range.contains($0.date) }
    }

    func holidays(inYear year: Int) -> [Holiday] {
        if let cached = cache[year] {
            return cached
        }
        let computed = KoreanHolidays.holidays(inYear: year, overrides: overrides)
        cache[year] = computed
        return computed
    }

    /// 하루에 한 번까지 저장소에서 새 보정 자료를 받아 온다. 실패하면 조용히 넘어간다.
    func refreshIfNeeded(now: Date = Date()) async {
        guard allowsRemoteUpdate else { return }
        if let lastCheck = defaults.object(forKey: Keys.lastCheck) as? Date, now.timeIntervalSince(lastCheck) < 24 * 3600 {
            return
        }
        defaults.set(now, forKey: Keys.lastCheck)

        var request = URLRequest(url: Self.remoteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        if let etag = defaults.string(forKey: Keys.etag) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        guard let result = try? await URLSession.shared.data(for: request),
              let response = result.1 as? HTTPURLResponse, response.statusCode == 200,
              let fetched = try? JSONDecoder().decode(HolidayOverrides.self, from: result.0),
              fetched.version > overrides.version
        else { return }

        if let etag = response.value(forHTTPHeaderField: "ETag") {
            defaults.set(etag, forKey: Keys.etag)
        }
        try? FileManager.default.createDirectory(at: Self.savedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? result.0.write(to: Self.savedURL, options: .atomic)
        overrides = fetched
        cache = [:]
    }

    private static var savedURL: URL {
        URL.applicationSupportDirectory.appending(path: "holidays/KR-overrides.json")
    }

    private static func load(from url: URL?) -> HolidayOverrides? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HolidayOverrides.self, from: data)
    }
}
