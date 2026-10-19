import DayGridCore
import SwiftData
import SwiftUI

/// 생일 추가와 편집. `person`이 `nil`이면 새로 만든다.
struct PersonEditView: View {
    let person: Person?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppClock.self) private var clock
    @State private var name: String
    @State private var isLunar: Bool
    @State private var month: Int
    @State private var day: Int
    @State private var isLeapMonth: Bool
    @State private var knowsYear: Bool
    @State private var year: Int
    @State private var isConfirmingDeletion = false

    init(person: Person?) {
        self.person = person
        _name = State(initialValue: person?.name ?? "")
        _isLunar = State(initialValue: person?.isLunar ?? false)
        _month = State(initialValue: person?.birthMonth ?? 1)
        _day = State(initialValue: person?.birthDay ?? 1)
        _isLeapMonth = State(initialValue: person?.isLeapMonth ?? false)
        _knowsYear = State(initialValue: (person?.birthYear ?? 0) > 0)
        _year = State(initialValue: (person?.birthYear ?? 0) > 0 ? person!.birthYear : 1990)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("이름") {
                    TextField("이름", text: $name)
                        .accessibilityIdentifier("person.name")
                }

                Section {
                    Picker("달력", selection: $isLunar) {
                        Text("양력").tag(false)
                        Text("음력").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Picker("월", selection: $month) {
                        ForEach(1...12, id: \.self) { Text("\($0)월").tag($0) }
                    }
                    Picker("일", selection: $day) {
                        ForEach(1...maxDay, id: \.self) { Text("\($0)일").tag($0) }
                    }
                    if isLunar {
                        Toggle("윤달", isOn: $isLeapMonth)
                    } else {
                        Toggle("태어난 해", isOn: $knowsYear)
                        if knowsYear {
                            Picker("연도", selection: $year) {
                                ForEach((1900...clock.today.year).reversed(), id: \.self) { Text(String($0)).tag($0) }
                            }
                        }
                    }
                } header: {
                    Text("생일")
                } footer: {
                    Text(nextBirthdayText)
                }

                if let person {
                    Section {
                        Button("삭제", role: .destructive) {
                            isConfirmingDeletion = true
                        }
                        .confirmationDialog("이 생일을 삭제할까요?", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
                            Button("삭제", role: .destructive) {
                                modelContext.delete(person)
                                try? modelContext.save()
                                dismiss()
                            }
                        }
                    } footer: {
                        if person.contactIdentifier != nil {
                            Text("연락처에서 가져온 생일입니다. 연락처에서 다시 가져오면 연락처 내용으로 바뀝니다.")
                        }
                    }
                }
            }
            .navigationTitle(person == nil ? "새 생일" : "생일 편집")
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
            .onChange(of: maxDay) { _, newMax in
                day = min(day, newMax)
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 음력은 30일까지, 양력은 그 달의 일수(2월은 29일까지).
    private var maxDay: Int {
        isLunar ? 30 : LocalDate.numberOfDays(inMonth: month, year: 2024)
    }

    private var birthday: Birthday {
        Birthday(month: month, day: min(day, maxDay), isLunar: isLunar, isLeapMonth: isLeapMonth)
    }

    private var nextBirthdayText: String {
        guard let next = birthday.nextOccurrence(onOrAfter: clock.today) else { return "" }
        let left = clock.today.days(until: next)
        return "다음 생일: \(next.koreanLongText) · \(left == 0 ? "오늘" : "D-\(left)")"
    }

    private func save() {
        let birthYear = !isLunar && knowsYear ? year : 0
        if let person {
            person.name = trimmedName
            person.birthday = birthday
            person.birthYear = birthYear
        } else {
            modelContext.insert(Person(name: trimmedName, birthday: birthday, birthYear: birthYear))
        }
        try? modelContext.save()
        dismiss()
    }
}
