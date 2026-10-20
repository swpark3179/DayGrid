import DayGridCore
import SwiftUI
import UIKit

struct SettingsTab: View {
    @AppStorage(AppSettings.firstWeekdayKey) private var firstWeekday = 1
    @Environment(AppClock.self) private var clock
    @AppStorage(AppSettings.birthdayReminderKey) private var birthdayReminder = -1
    @AppStorage(AppSettings.dayDetailStyleKey) private var dayDetailStyle = DayDetailStyle.list
    @AppStorage(AppSettings.workdayStartMinuteKey) private var workdayStart = AppSettings.defaultWorkdayStartMinute
    @AppStorage(AppSettings.workdayEndMinuteKey) private var workdayEnd = AppSettings.defaultWorkdayEndMinute
    /// 동기화 오류 내용을 복사한 뒤 버튼 문구를 바꾼다.
    @State private var copiedSyncReport: String?

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
                dayDetailSection
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

    /// 하루 상세 보기 방식. 타임라인이면 업무 시간도 정한다. 종료는 시작보다 30분 이상 늦게만 고를 수 있다.
    private var dayDetailSection: some View {
        Section {
            Picker("보기 방식", selection: $dayDetailStyle) {
                ForEach(DayDetailStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .accessibilityIdentifier("settings.dayDetailStyle")
            if dayDetailStyle == .timeline {
                DatePicker(
                    "업무 시작 시간",
                    selection: timeBinding($workdayStart),
                    in: ...date(ofMinute: 23 * 60),
                    displayedComponents: .hourAndMinute
                )
                .accessibilityIdentifier("settings.workdayStart")
                DatePicker(
                    "업무 종료 시간",
                    selection: timeBinding($workdayEnd),
                    in: date(ofMinute: workdayStart + 30)...,
                    displayedComponents: .hourAndMinute
                )
                .accessibilityIdentifier("settings.workdayEnd")
            }
        } header: {
            Text("하루 상세")
        } footer: {
            Text("타임라인은 시간을 정한 일정과 할일을 업무 시간 안의 시각 위치에 놓습니다. 업무 시간 밖의 일정이 있으면 그 시각까지 넓혀 보여 주고, 시간이 없는 일정은 아래에 목록으로 보여 줍니다.")
        }
        .onChange(of: workdayStart) { _, start in
            if workdayEnd < start + 30 {
                workdayEnd = min(start + 60, 23 * 60 + 59)
            }
        }
    }

    /// 자정부터 지난 분 ↔ 오늘의 그 시각(`RecurringTaskEditView`의 알림 시각과 같은 방식). DatePicker가 시각만 보여 주므로 날짜는 상관없다.
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { date(ofMinute: minutes.wrappedValue) },
            set: { minutes.wrappedValue = LocalDate.minuteOfDay($0) }
        )
    }

    private func date(ofMinute minute: Int) -> Date {
        let minute = min(max(minute, 0), 23 * 60 + 59)
        return clock.today.date(hour: minute / 60, minute: minute % 60)
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
            // 오류를 펼친 내용(안쪽 CloudKit 오류와 서버 문구). 붙여 넣어 원인을 알릴 수 있다.
            if let report = state.failureReport {
                Button(copiedSyncReport == report ? "복사했습니다" : "오류 내용 복사") {
                    UIPasteboard.general.string = report
                    copiedSyncReport = report
                }
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
