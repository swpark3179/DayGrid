import DayGridCore
import SwiftData
import SwiftUI

/// 반복 할일 목록. 지금 주기를 체크하고, 규칙에 맞는 기간(이번 주·이번 달·올해)의 완료 수를 본다. 누르면 규칙을 고친다.
struct RecurringTab: View {
    @Environment(AppClock.self) private var clock
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\RecurringTask.sortOrder), SortDescriptor(\RecurringTask.createdAt)])
    private var tasks: [RecurringTask]
    @State private var editingTask: RecurringTask?
    @State private var isAddingTask = false

    var body: some View {
        let active = tasks.filter { $0.isActive }
        let paused = tasks.filter { !$0.isActive }

        NavigationStack {
            List {
                if tasks.isEmpty {
                    ContentUnavailableView(
                        "반복 할일 없음",
                        systemImage: "repeat",
                        description: Text("+ 버튼으로 매일, 매주, 매월 할 일을 만드세요.")
                    )
                    .listRowBackground(Color.clear)
                }
                if !active.isEmpty {
                    Section("진행 중") {
                        ForEach(active) { row($0) }
                    }
                }
                if !paused.isEmpty {
                    Section("중지됨") {
                        ForEach(paused) { row($0) }
                    }
                }
            }
            .accessibilityIdentifier("recurring.list")
            .navigationTitle("반복")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("반복 할일 추가", systemImage: "plus") {
                        isAddingTask = true
                    }
                    .accessibilityIdentifier("recurring.add")
                }
            }
            .sheet(item: $editingTask) { task in
                RecurringTaskEditView(task: task)
            }
            .sheet(isPresented: $isAddingTask) {
                RecurringTaskEditView(task: nil)
            }
        }
    }

    private func row(_ task: RecurringTask) -> some View {
        RecurringTaskRow(task: task, date: clock.today, today: clock.today, showsSummary: true)
            .contentShape(Rectangle())
            .onTapGesture {
                editingTask = task
            }
            .swipeActions {
                Button("삭제", role: .destructive) {
                    modelContext.delete(task)
                    try? modelContext.save()
                }
            }
    }
}

/// 반복 할일 한 줄. `date`가 속한 주기의 상태를 보여주고, 그 주기가 지금 주기면 체크할 수 있다.
struct RecurringTaskRow: View {
    let task: RecurringTask
    let date: LocalDate
    let today: LocalDate
    var showsSummary = false

    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettings.firstWeekdayKey) private var firstWeekday = 1

    var body: some View {
        let current = task.isActive ? task.cycleStatus(on: date, today: today) : nil
        HStack(spacing: 12) {
            marker(current)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .foregroundStyle(task.isActive ? Color.primary : Color.secondary)
                Text(detailText(current))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if showsSummary, task.isActive, let summary {
                HStack(spacing: 6) {
                    SummaryProgressRing(fraction: summary.fraction)
                    // UI 테스트가 "이번 주 1/7" 같은 글자로 찾는다. 숫자만 굴러가게 한다.
                    Text(verbatim: summary.koreanText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(summary.done)))
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func marker(_ current: (cycle: RecurrenceCycle, status: RecurrenceStatus)?) -> some View {
        if let current, current.cycle.contains(today) {
            let isDone = Self.isDone(current.status)
            Button {
                // 상세 문구와 기간 요약도 함께 바뀌도록 애니메이션 안에서 바꾼다.
                withAnimation(.snappy) {
                    task.toggleCompletion(of: current.cycle, today: today, in: modelContext)
                }
            } label: {
                CompletionCheckmark(isDone: isDone)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isDone ? "완료 취소" : "완료로 표시")
        } else {
            Image(systemName: Self.symbol(for: current?.status))
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private static func isDone(_ status: RecurrenceStatus) -> Bool {
        if case .done = status {
            return true
        }
        return false
    }

    private static func symbol(for status: RecurrenceStatus?) -> String {
        switch status {
        case .done: "checkmark.circle.fill"
        case .missed: "xmark.circle"
        case .pending, .upcoming, nil: "repeat.circle"
        }
    }

    private func detailText(_ current: (cycle: RecurrenceCycle, status: RecurrenceStatus)?) -> String {
        var parts = [task.rule.koreanText]
        switch current?.status {
        case .done(let completedOn):
            parts.append("\(completedOn.koreanMonthDayText) 완료")
        case .pending(let dayNumber):
            parts.append(dayNumber == 1 ? "오늘 시작" : "\(dayNumber)일째")
        case .missed:
            parts.append("놓침")
        case .upcoming:
            parts.append("예정")
        case nil:
            if !task.isActive {
                parts.append("중지됨")
            } else if let next = nextStart {
                parts.append("다음 \(next.koreanMonthDayWeekdayText)")
            }
        }
        return parts.joined(separator: " · ")
    }

    private var nextStart: LocalDate? {
        task.recurrence?.occurrences(in: today...today.adding(days: 62)).first
    }

    /// 오늘이 속한 요약 기간(매일·요일 여럿인 매주는 이번 주, 요일 하나인 매주는 이번 달, 매월은 올해)의 완료 수와 주기 수.
    /// 그 기간에 주기가 없으면 `nil`.
    private var summary: RecurrenceSummary? {
        task.recurrence?.summary(on: today, firstWeekday: firstWeekday, completedCycleStarts: Set(task.completionDays.keys))
    }
}

/// 기간 완료 비율을 보여 주는 작은 링. 글자("이번 주 2/7")가 같은 내용을 읽어 주므로 VoiceOver에서는 숨긴다.
private struct SummaryProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}
