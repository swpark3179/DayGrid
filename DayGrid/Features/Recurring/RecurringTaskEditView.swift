import DayGridCore
import SwiftData
import SwiftUI

/// 반복 할일 만들기와 고치기. `task`가 `nil`이면 새로 만든다.
struct RecurringTaskEditView: View {
    let task: RecurringTask?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppClock.self) private var clock
    @Query(sort: \ItemCategory.sortOrder) private var categories: [ItemCategory]
    @State private var title: String
    /// 0 = 매일, 1 = 매주, 2 = 매월
    @State private var kind: Int
    @State private var weekdays: Set<Int>
    /// 1–31, 0 = 말일
    @State private var monthDay: Int
    @State private var start: Date?
    @State private var hasEnd: Bool
    @State private var end: Date?
    @State private var categoryID: UUID?
    @State private var isActive: Bool
    @State private var isConfirmingDeletion = false

    init(task: RecurringTask?) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _kind = State(initialValue: task?.ruleKind ?? 0)
        let weekdays: Set<Int>
        if case .weekly(let chosen) = task?.rule {
            weekdays = chosen
        } else {
            weekdays = []
        }
        _weekdays = State(initialValue: weekdays)
        _monthDay = State(initialValue: task?.monthDay ?? 1)
        _start = State(initialValue: task?.startDay?.date(hour: 12))
        _hasEnd = State(initialValue: task?.endDay != nil)
        _end = State(initialValue: task?.endDay?.date(hour: 12))
        _categoryID = State(initialValue: task?.category?.id)
        _isActive = State(initialValue: task?.isActive ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("제목") {
                    TextField("예: 물 2L 마시기", text: $title)
                        .accessibilityIdentifier("recurring.title")
                }

                Section("반복") {
                    Picker("주기", selection: $kind) {
                        Text("매일").tag(0)
                        Text("매주").tag(1)
                        Text("매월").tag(2)
                    }
                    .pickerStyle(.segmented)
                    switch kind {
                    case 1:
                        weekdayPicker
                    case 2:
                        Picker("날짜", selection: $monthDay) {
                            ForEach(1...31, id: \.self) { Text("\($0)일").tag($0) }
                            Text("말일").tag(0)
                        }
                    default:
                        EmptyView()
                    }
                }

                Section {
                    DatePicker("시작", selection: startBinding, displayedComponents: .date)
                    Toggle("종료일", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("종료", selection: endBinding, in: startBinding.wrappedValue..., displayedComponents: .date)
                    }
                } header: {
                    Text("기간")
                } footer: {
                    Text(ruleSummary)
                }

                Section {
                    Picker("카테고리", selection: $categoryID) {
                        Text("없음").tag(UUID?.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    if task != nil {
                        Toggle("사용", isOn: $isActive)
                    }
                }

                if let task {
                    Section {
                        Button("삭제", role: .destructive) {
                            isConfirmingDeletion = true
                        }
                        .confirmationDialog("이 반복 할일과 완료 기록을 삭제할까요?", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
                            Button("삭제", role: .destructive) {
                                modelContext.delete(task)
                                try? modelContext.save()
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(task == nil ? "새 반복 할일" : "반복 할일 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if task == nil {
                    if weekdays.isEmpty { weekdays = [clock.today.weekday] }
                    if categoryID == nil { categoryID = categories.first?.id }
                    monthDay = clock.today.day
                }
            }
        }
    }

    /// 일요일부터 토요일까지 요일 버튼. 여러 개를 고를 수 있다.
    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { weekday in
                let isOn = weekdays.contains(weekday)
                Button {
                    if isOn {
                        weekdays.remove(weekday)
                    } else {
                        weekdays.insert(weekday)
                    }
                } label: {
                    Text(LocalDate.koreanWeekdaySymbols[weekday - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(isOn ? Color.white : DayStyle.color(forWeekday: weekday))
                        .background(isOn ? Color.accentColor : Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private var rule: RecurrenceRule {
        switch kind {
        case 1: .weekly(weekdays: weekdays)
        case 2: monthDay == 0 ? .monthlyLastDay : .monthly(day: monthDay)
        default: .daily
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !(kind == 1 && weekdays.isEmpty)
    }

    /// "매주 월·수·금 · 10월 19일부터"
    private var ruleSummary: String {
        let startDay = LocalDate(startBinding.wrappedValue)
        var text = "\(rule.koreanText) · \(startDay.koreanMonthDayText)부터"
        if hasEnd {
            text += " \(LocalDate(endBinding.wrappedValue).koreanMonthDayText)까지"
        }
        return text
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { start ?? clock.today.date(hour: 12) },
            set: { start = $0 }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { max(end ?? startBinding.wrappedValue, startBinding.wrappedValue) },
            set: { end = $0 }
        )
    }

    private func save() {
        let startDay = LocalDate(startBinding.wrappedValue)
        let item = task ?? RecurringTask(title: "", rule: rule, startDay: startDay)
        item.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.rule = rule
        item.startDayKey = startDay.yyyymmdd
        item.endDayKey = hasEnd ? max(startDay, LocalDate(endBinding.wrappedValue)).yyyymmdd : 0
        item.category = categories.first { $0.id == categoryID }
        item.isActive = isActive
        if task == nil {
            modelContext.insert(item)
        }
        try? modelContext.save()
        dismiss()
    }
}
