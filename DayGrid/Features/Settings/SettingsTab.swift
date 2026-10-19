import SwiftUI

struct SettingsTab: View {
    @AppStorage(AppSettings.firstWeekdayKey) private var firstWeekday = 1
    @Environment(AppClock.self) private var clock

    var body: some View {
        NavigationStack {
            List {
                Section("달력") {
                    Picker("주 시작 요일", selection: $firstWeekday) {
                        Text("일요일").tag(1)
                        Text("월요일").tag(2)
                    }
                    NavigationLink("카테고리") {
                        CategoryListView()
                    }
                }
                Section("기념일") {
                    NavigationLink("생일") {
                        BirthdayListView(today: clock.today)
                    }
                    NavigationLink("개인 휴일") {
                        PersonalHolidayListView()
                    }
                }
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
