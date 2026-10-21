import DayGridCore
import SwiftData
import SwiftUI

/// 첫 화면. 좌우로 넘기는 월간 달력.
struct CalendarTab: View {
    let today: LocalDate
    /// 값이 들어오면 그 달로 넘기고 하루 상세를 연다(알림을 눌렀을 때).
    @Binding var dayToOpen: LocalDate?

    @AppStorage(AppSettings.firstWeekdayKey) private var firstWeekday = 1
    @Query private var people: [Person]
    @State private var selectedMonth: Int
    @State private var selectedDay: DaySelection?
    @State private var editorMode: ItemEditorView.Mode?
    @State private var isShowingBirthdays = false
    @State private var isPickingMonth = false
    @State private var droppedCount = 0
    @Environment(\.modelContext) private var modelContext

    /// 오늘 기준 앞뒤로 넘길 수 있는 달 수.
    private static let monthsAroundToday = 120

    init(today: LocalDate, dayToOpen: Binding<LocalDate?> = .constant(nil)) {
        self.today = today
        _dayToOpen = dayToOpen
        _selectedMonth = State(initialValue: today.monthIndex)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                upcomingBirthdayBanner
                WeekdayHeader(firstWeekday: firstWeekday)
                TabView(selection: $selectedMonth) {
                    ForEach(monthRange, id: \.self) { index in
                        MonthPageView(
                            month: LocalDate(firstDayOfMonthIndex: index),
                            today: today,
                            firstWeekday: firstWeekday,
                            onSelectDay: { selectedDay = DaySelection(date: $0) },
                            onAddItem: { editorMode = .new($0) },
                            onAddRange: { editorMode = .newRange($0, $1) },
                            onPage: { page(by: $0) },
                            onDropItem: scheduleDroppedItem
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .sensoryFeedback(.success, trigger: droppedCount)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedDay) { selection in
                // 시트 높이(보통 medium/large, 옮기는 동안 작게)는 DayDetailView가 정한다.
                DayDetailView(date: selection.date)
            }
            .onAppear {
                // 하루 상세에서 꾹 눌러 옮기다가 가장자리에 머무르면 달을 넘긴다.
                CalendarDropState.shared.onPage = { delta in page(by: delta) }
            }
            .sheet(item: $editorMode) { mode in
                ItemEditorView(mode: mode)
            }
            .onChange(of: dayToOpen, initial: true) { _, day in
                guard let day else { return }
                dayToOpen = nil
                selectedMonth = day.monthIndex
                selectedDay = DaySelection(date: day)
            }
            .sheet(isPresented: $isPickingMonth) {
                MonthPickerSheet(selectedMonth: selectedMonth, todayMonth: today.monthIndex, range: monthRange) { index in
                    // 먼 달로 건너뛸 때 사이의 달을 모두 넘기는 애니메이션은 하지 않는다.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        selectedMonth = index
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $isShowingBirthdays) {
                NavigationStack {
                    BirthdayListView(today: today)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("닫기") { isShowingBirthdays = false }
                            }
                        }
                }
            }
        }
    }

    /// 30일 안에 생일인 사람이 있으면 헤더 아래에 한 줄로 알린다. 누르면 생일 목록이 열린다.
    @ViewBuilder
    private var upcomingBirthdayBanner: some View {
        let names = Dictionary(people.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let upcoming = UpcomingBirthday.list(people.map { (id: $0.id, birthday: $0.birthday) }, today: today)
            .sorted { ($0.daysLeft, names[$0.id] ?? "") < ($1.daysLeft, names[$1.id] ?? "") }
        if let first = upcoming.first, let name = names[first.id] {
            Button {
                isShowingBirthdays = true
            } label: {
                HStack(spacing: 6) {
                    Text("🎂")
                    Text(upcoming.count > 1
                        ? "\(name) \(first.koreanDDay) 외 \(upcoming.count - 1)명"
                        : "\(name) \(first.koreanDDay)")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 6)
            .accessibilityIdentifier("calendar.birthdays")
        }
    }

    /// 이전·다음 달로 넘긴다(끌기 중 가장자리에 머무를 때).
    private func page(by delta: Int) {
        let next = selectedMonth + delta
        guard monthRange.contains(next) else { return }
        withAnimation {
            selectedMonth = next
        }
    }

    /// "나중에"에서 끌어 온 항목을 그 날로 넣는다. 미룰 때 남긴 모양(종일·시간, 길이)을 그대로 쓴다.
    private func scheduleDroppedItem(_ id: UUID, on day: LocalDate) {
        var descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let item = try? modelContext.fetch(descriptor).first, !item.isScheduled else { return }
        item.schedule(on: day, using: item.scheduleHint)
        try? modelContext.save()
        droppedCount += 1
    }

    /// 헤더의 + 버튼으로 추가할 날짜. 이번 달을 보고 있으면 오늘, 아니면 보고 있는 달의 1일.
    private var dayForNewItem: LocalDate {
        selectedMonth == today.monthIndex ? today : LocalDate(firstDayOfMonthIndex: selectedMonth)
    }

    private var monthRange: ClosedRange<Int> {
        (today.monthIndex - Self.monthsAroundToday)...(today.monthIndex + Self.monthsAroundToday)
    }

    /// 왼쪽 위 연·월. 누르면 연·월을 골라 바로 이동한다.
    /// 제목 글자는 UI 테스트가 찾는 그대로 두고, 옆의 화살표 버튼이 접근성 동작을 맡는다.
    private var header: some View {
        HStack {
            HStack(spacing: 4) {
                Text(LocalDate(firstDayOfMonthIndex: selectedMonth).koreanMonthTitle)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Button("연·월 선택", systemImage: "chevron.down") {
                    isPickingMonth = true
                }
                .labelStyle(.iconOnly)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("calendar.monthTitle")
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isPickingMonth = true
            }
            Spacer()
            Button("새 일정", systemImage: "plus") {
                editorMode = .new(dayForNewItem)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .accessibilityIdentifier("calendar.add")
            Button("오늘") {
                withAnimation {
                    selectedMonth = today.monthIndex
                }
            }
            .buttonStyle(.bordered)
            .disabled(selectedMonth == today.monthIndex)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// 일 월 화 … 요일 이름 줄.
struct WeekdayHeader: View {
    let firstWeekday: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                let weekday = (startWeekday - 1 + offset) % 7 + 1
                Text(LocalDate.koreanWeekdaySymbols[weekday - 1])
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DayStyle.color(forWeekday: weekday))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    private var startWeekday: Int {
        (1...7).contains(firstWeekday) ? firstWeekday : 1
    }
}

enum DayStyle {
    /// 공휴일 숫자와 이름. 일요일과 같은 빨강이다.
    static let publicHolidayColor = Color.red
    /// 개인 휴일 숫자와 이름(사용자 결정: 공휴일과 구별되는 주황)
    static let personalHolidayColor = Color.orange

    /// 날짜 숫자 색: 공휴일 빨강 → 개인 휴일 주황 → 요일 색
    static func numberColor(for date: LocalDate, mark: DayMark?) -> Color {
        if mark?.isPublicHoliday == true { return publicHolidayColor }
        if mark?.isPersonalHoliday == true { return personalHolidayColor }
        return color(forWeekday: date.weekday)
    }

    /// 일요일은 빨강, 토요일은 파랑.
    static func color(forWeekday weekday: Int) -> Color {
        switch weekday {
        case 1: .red
        case 7: .blue
        default: .primary
        }
    }
}

/// 하루 상세 시트를 띄우기 위한 선택값.
struct DaySelection: Identifiable {
    let date: LocalDate

    var id: Int { date.yyyymmdd }
}
