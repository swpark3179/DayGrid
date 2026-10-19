import SwiftUI

struct SettingsTab: View {
    var body: some View {
        NavigationStack {
            List {
                Section("정보") {
                    LabeledContent("버전", value: Self.versionText)
                }
            }
            .navigationTitle("설정")
        }
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }
}
