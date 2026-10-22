import DayGridCore
import SwiftData
import SwiftUI

/// 반복 할일 목록. 지금 주기를 체크하고, 이번 달 완료 수를 본다. 누르면 규칙을 고친다.
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
        RecurringTaskRow(task: task, date: clock.today, today: clock.today, showsMonthSummary: true)
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
    var showsMonthSummary = false

    @Environment(\.modelContext) private var modelContext

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
            if showsMonthSummary, task.isActive, let summary = monthSummary {
                HStack(spacing: 6) {
                    MonthProgressRing(fraction: Double(summary.done) / Double(summary.total))
                    // UI 테스트가 "이번 달"로 시작하는 글자를 찾는다. 숫자만 굴러가게 한다.
                    Text(verbatim: "이번 달 \(summary.done)/\(summary.total)")
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
                // 상세 문구와 이번 달 요약도 함께 바뀌도록 애니메이션 안에서 바꾼다.
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

    /// 이번 달 완료 수와 주기 수. 이번 달에 주기가 없으면 `nil`.
    private var monthSummary: (done: Int, total: Int)? {
        guard let recurrence = task.recurrence else { return nil }
        let summary = recurrence.monthSummary(month: today, today: today, completedCycleStarts: Set(task.completionDays.keys))
        return summary.total > 0 ? summary : nil
    }
}

/// 이번 달 완료 비율을 보여 주는 작은 링. 글자("이번 달 5/15")가 같은 내용을 읽어 주므로 VoiceOver에서는 숨긴다.
private struct MonthProgressRing: View {
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
