import DayGridCore
import SwiftUI

struct SettingsTab: View {
    @AppStorage(AppSettings.firstWeekdayKey) private var firstWeekday = 1
    @Environment(AppClock.self) private var clock
    @AppStorage(AppSettings.birthdayReminderKey) private var birthdayReminder = -1

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
                Section {
                    Picker("생일 알림", selection: $birthdayReminder) {
                        Text("끔").tag(-1)
                        Text("당일").tag(0)
                        Text("당일, 1일 전").tag(1)
                        Text("당일, 3일 전").tag(3)
                        Text("당일, 7일 전").tag(7)
                    }
                    Button("시스템 알림 설정 열기") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Text("알림")
                } footer: {
                    Text("생일 알림은 오전 9시에 옵니다. 일정 알림은 일정 편집 화면에서, 반복 할일 알림은 반복 할일 편집 화면에서 정합니다.")
                }
                .onChange(of: birthdayReminder) { _, value in
                    if value >= 0 {
                        Task { await NotificationScheduler.shared.requestAuthorization() }
                    }
                    NotificationScheduler.shared.scheduleSync(after: .zero)
                }
                syncSection
                Section("정보") {
                    LabeledContent("버전", value: Self.versionText)
                }
            }
            .navigationTitle("설정")
        }
    }

    /// iCloud 동기화 상태. 끄는 스위치는 없다(항상 켬). "최근 동기화: n분 전"은 1분마다 다시 그린다.
    private var syncSection: some View {
        let state = CloudSyncMonitor.shared.state
        return Section {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                LabeledContent("iCloud", value: state.koreanSummary(now: context.date))
                    .accessibilityIdentifier("settings.sync")
            }
            if let detail = state.koreanDetail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("동기화")
        } footer: {
            Text("iCloud에 로그인되어 있으면 일정, 할일, 생일, 반복 할일이 같은 Apple ID를 쓰는 기기와 자동으로 맞춰집니다.")
        }
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }
}
