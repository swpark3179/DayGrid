import Foundation
import Testing

/// App Store에 올리는 앱 번들에는 개인정보 매니페스트(`PrivacyInfo.xcprivacy`)가 있어야 한다.
/// 이유가 필요한 API(UserDefaults 등)를 쓰면서 이유를 적지 않으면 App Store Connect가 빌드를 거절한다.
/// 단위 테스트는 앱을 호스트로 띄우므로 `Bundle.main`이 앱 번들이다.
struct PrivacyManifestTests {
    @Test func appBundleHasThePrivacyManifest() throws {
        let url = try #require(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "앱 번들에 PrivacyInfo.xcprivacy가 있어야 한다(project.yml의 리소스)"
        )
        let object = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        let manifest = try #require(object as? [String: Any])
        #expect(manifest["NSPrivacyTracking"] as? Bool == false, "추적하지 않는다")
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true, "개발자가 모으는 데이터가 없다")

        let apis = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        let userDefaults = apis.first { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults" }
        let reasons = userDefaults?["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
        #expect(reasons.contains("CA92.1"), "@AppStorage(UserDefaults)를 쓰는 이유 CA92.1이 있어야 한다")
    }
}
