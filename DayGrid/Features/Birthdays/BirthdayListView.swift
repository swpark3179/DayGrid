import DayGridCore
import SwiftData
import SwiftUI

/// 생일 목록. 30일 안의 생일을 위에 따로 모으고, 나머지는 다음 생일이 가까운 순으로 보여준다.
/// 직접 추가하거나 연락처에서 가져올 수 있다.
struct BirthdayListView: View {
    let today: LocalDate

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.name) private var people: [Person]
    @State private var editingPerson: Person?
    @State private var isAddingPerson = false
    @State private var isImporting = false
    @State private var importMessage: String?

    var body: some View {
        let rows = people
            .map { BirthdayRow(person: $0, today: today) }
            .sorted { ($0.daysLeft, $0.person.name) < ($1.daysLeft, $1.person.name) }
        let upcoming = rows.filter { $0.daysLeft <= 30 }
        let later = rows.filter { $0.daysLeft > 30 }

        List {
            if rows.isEmpty {
                ContentUnavailableView(
                    "생일 없음",
                    systemImage: "gift",
                    description: Text("+ 버튼으로 직접 넣거나 연락처에서 가져오세요.")
                )
                .listRowBackground(Color.clear)
            }
            if !upcoming.isEmpty {
                Section("다가오는 생일") {
                    ForEach(upcoming) { row($0) }
                }
            }
            if !later.isEmpty {
                Section("전체") {
                    ForEach(later) { row($0) }
                }
            }
        }
        .accessibilityIdentifier("birthdays.list")
        .navigationTitle("생일")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("직접 추가", systemImage: "square.and.pencil") {
                        isAddingPerson = true
                    }
                    Button("연락처에서 가져오기", systemImage: "person.crop.circle.badge.plus") {
                        Task { await importContacts() }
                    }
                } label: {
                    Label("추가", systemImage: "plus")
                }
                .disabled(isImporting)
                .accessibilityIdentifier("birthdays.add")
            }
        }
        .overlay {
            if isImporting {
                ProgressView("연락처를 읽는 중")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .sheet(item: $editingPerson) { person in
            PersonEditView(person: person)
        }
        .sheet(isPresented: $isAddingPerson) {
            PersonEditView(person: nil)
        }
        .alert(
            "연락처 가져오기",
            isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    private func row(_ row: BirthdayRow) -> some View {
        Button {
            editingPerson = row.person
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(row.person.name)
                            .foregroundStyle(Color.primary)
                        if row.person.contactIdentifier != nil {
                            Image(systemName: "person.crop.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("연락처에서 가져옴")
                        }
                    }
                    Text(row.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(row.dDay)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(row.daysLeft <= 7 ? Color.pink : Color.secondary)
            }
        }
        .swipeActions {
            Button("삭제", role: .destructive) {
                modelContext.delete(row.person)
                try? modelContext.save()
            }
        }
    }

    private func importContacts() async {
        isImporting = true
        defer { isImporting = false }
        do {
            importMessage = try await ContactsImporter.importBirthdays(into: modelContext).text
        } catch ContactsImporter.ImportError.accessDenied {
            importMessage = "연락처 접근이 허용되지 않았습니다. 설정 앱 → DayGrid에서 연락처 접근을 허용해 주세요."
        } catch {
            importMessage = "연락처를 읽지 못했습니다. \(error.localizedDescription)"
        }
    }
}

private struct BirthdayRow: Identifiable {
    let person: Person
    let next: LocalDate?
    /// 다음 생일까지 남은 날. 계산할 수 없으면 맨 뒤로 보낸다.
    let daysLeft: Int

    init(person: Person, today: LocalDate) {
        self.person = person
        next = person.birthday.nextOccurrence(onOrAfter: today)
        daysLeft = next.map { today.days(until: $0) } ?? Int.max
    }

    var id: UUID { person.id }

    var detail: String {
        guard let next else { return person.birthday.koreanText }
        let ordinal = person.ordinalText(on: next).map { " · \($0)" } ?? ""
        return person.birthday.isLunar
            ? "\(person.birthday.koreanText) · \(next.koreanMonthDayWeekdayText)\(ordinal)"
            : "\(next.koreanMonthDayWeekdayText)\(ordinal)"
    }

    var dDay: String {
        switch daysLeft {
        case 0: "오늘"
        case Int.max: ""
        default: "D-\(daysLeft)"
        }
    }
}
