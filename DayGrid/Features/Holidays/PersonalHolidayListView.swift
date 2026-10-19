import DayGridCore
import SwiftData
import SwiftUI

/// 설정 → 개인 휴일. 회사 휴가처럼 나만의 쉬는 날을 관리한다. 달력에서 공휴일처럼 빨갛게 표시된다.
struct PersonalHolidayListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppClock.self) private var clock
    @Query(sort: \PersonalHoliday.startDayKey) private var holidays: [PersonalHoliday]
    @State private var editingHoliday: PersonalHoliday?
    @State private var isAddingHoliday = false

    var body: some View {
        let todayKey = clock.today.yyyymmdd
        let upcoming = holidays.filter { $0.endDayKey >= todayKey }
        let past = holidays.filter { $0.endDayKey < todayKey }.reversed()

        List {
            if holidays.isEmpty {
                ContentUnavailableView(
                    "개인 휴일 없음",
                    systemImage: "sun.max",
                    description: Text("+ 버튼으로 휴가나 회사 휴무일을 추가하세요.")
                )
                .listRowBackground(Color.clear)
            }
            if !upcoming.isEmpty {
                Section("다가오는 휴일") {
                    ForEach(upcoming) { row($0) }
                }
            }
            if !past.isEmpty {
                Section("지난 휴일") {
                    ForEach(Array(past)) { row($0) }
                }
            }
        }
        .accessibilityIdentifier("holidays.list")
        .navigationTitle("개인 휴일")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("추가", systemImage: "plus") {
                    isAddingHoliday = true
                }
            }
        }
        .sheet(item: $editingHoliday) { holiday in
            PersonalHolidayEditView(holiday: holiday)
        }
        .sheet(isPresented: $isAddingHoliday) {
            PersonalHolidayEditView(holiday: nil)
        }
    }

    private func row(_ holiday: PersonalHoliday) -> some View {
        Button {
            editingHoliday = holiday
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(holiday.name)
                    .foregroundStyle(Color.primary)
                Text(Self.rangeText(holiday))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions {
            Button("삭제", role: .destructive) {
                modelContext.delete(holiday)
                try? modelContext.save()
            }
        }
    }

    static func rangeText(_ holiday: PersonalHoliday) -> String {
        guard let start = holiday.startDay else { return "" }
        let end = holiday.endDay ?? start
        guard end > start else { return start.koreanLongText }
        return "\(start.koreanLongText) – \(end.koreanMonthDayWeekdayText) · \(start.days(until: end) + 1)일"
    }
}

/// 개인 휴일 추가와 편집. `holiday`가 `nil`이면 새로 만든다.
struct PersonalHolidayEditView: View {
    let holiday: PersonalHoliday?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppClock.self) private var clock
    @State private var name: String
    @State private var start: Date?
    @State private var end: Date?

    init(holiday: PersonalHoliday?) {
        self.holiday = holiday
        _name = State(initialValue: holiday?.name ?? "")
        _start = State(initialValue: holiday?.startDay?.date(hour: 12))
        _end = State(initialValue: (holiday?.endDay ?? holiday?.startDay)?.date(hour: 12))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("이름") {
                    TextField("예: 여름 휴가", text: $name)
                }
                Section("기간") {
                    DatePicker("시작", selection: startBinding, displayedComponents: .date)
                    DatePicker("종료", selection: endBinding, in: startBinding.wrappedValue..., displayedComponents: .date)
                }
                if let holiday {
                    Section {
                        Button("삭제", role: .destructive) {
                            modelContext.delete(holiday)
                            try? modelContext.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(holiday == nil ? "새 개인 휴일" : "개인 휴일 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 새로 만들 때는 오늘에서 시작한다(`clock`은 init에서 읽을 수 없어 처음 읽을 때 채운다).
    private var startBinding: Binding<Date> {
        Binding(
            get: { start ?? clock.today.date(hour: 12) },
            set: { newValue in
                let duration = endBinding.wrappedValue.timeIntervalSince(startBinding.wrappedValue)
                start = newValue
                end = newValue.addingTimeInterval(max(0, duration))
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { max(end ?? start ?? clock.today.date(hour: 12), start ?? clock.today.date(hour: 12)) },
            set: { end = $0 }
        )
    }

    private func save() {
        let startDay = LocalDate(startBinding.wrappedValue)
        let endDay = LocalDate(endBinding.wrappedValue)
        if let holiday {
            holiday.name = trimmedName
            holiday.setDays(from: startDay, through: endDay)
        } else {
            modelContext.insert(PersonalHoliday(name: trimmedName, from: startDay, through: endDay))
        }
        try? modelContext.save()
        dismiss()
    }
}
