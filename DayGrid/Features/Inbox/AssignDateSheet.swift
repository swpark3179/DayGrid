import DayGridCore
import SwiftData
import SwiftUI

/// "나중에" 항목에 날짜를 정하는 시트. 오늘·내일·이번 주말이나 직접 고른 날짜에,
/// 미룰 때 남긴 모양(종일 일수, 시작 시각과 길이)을 기본값으로 놓는다.
struct AssignDateSheet: View {
    let item: Item
    let today: LocalDate

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var day: LocalDate
    @State private var hint: ScheduleHint

    init(item: Item, today: LocalDate) {
        self.item = item
        self.today = today
        _day = State(initialValue: today)
        _hint = State(initialValue: item.scheduleHint)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("날짜") {
                    ForEach(QuickDay.allCases, id: \.self) { quickDay in
                        let date = quickDay.date(from: today)
                        Button {
                            day = date
                        } label: {
                            HStack {
                                Text(quickDay.koreanTitle)
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                Text(date.koreanMonthDayWeekdayText)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "checkmark")
                                    .opacity(day == date ? 1 : 0)
                            }
                        }
                        .accessibilityIdentifier("assign.\(quickDay.rawValue)")
                    }
                    DatePicker("날짜 선택", selection: dayBinding, displayedComponents: .date)
                }

                Section {
                    Toggle("종일", isOn: $hint.isAllDay)
                    if hint.isAllDay {
                        Stepper("기간 \(hint.dayCount)일", value: $hint.dayCount, in: 1...60)
                    } else {
                        DatePicker("시작", selection: startBinding, displayedComponents: .hourAndMinute)
                        LabeledContent("시간", value: timeRangeText)
                    }
                } footer: {
                    Text(summaryText)
                }
            }
            .navigationTitle("날짜 정하기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("정하기") { save() }
                        .accessibilityIdentifier("assign.save")
                }
            }
        }
    }

    private var dayBinding: Binding<Date> {
        Binding(
            get: { day.date(hour: 12) },
            set: { day = LocalDate($0) }
        )
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { hint.startDate(on: day) },
            set: { hint.startMinute = LocalDate.minuteOfDay($0) }
        )
    }

    private var timeRangeText: String {
        let start = hint.startDate(on: day)
        let end = hint.endDate(on: day)
        let nextDay = LocalDate(end.addingTimeInterval(-1)) > day ? " (다음 날)" : ""
        return "\(ItemTimeText.time(start)) – \(ItemTimeText.time(end))\(nextDay)"
    }

    private var summaryText: String {
        if hint.isAllDay {
            let endDay = hint.endDay(startingOn: day)
            return endDay == day
                ? "\(day.koreanMonthDayWeekdayText) 종일"
                : "\(day.koreanMonthDayWeekdayText) – \(endDay.koreanMonthDayWeekdayText)"
        }
        return "\(day.koreanMonthDayWeekdayText) \(timeRangeText)"
    }

    private func save() {
        item.schedule(on: day, using: hint)
        try? modelContext.save()
        dismiss()
    }
}
