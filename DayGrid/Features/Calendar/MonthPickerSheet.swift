import DayGridCore
import SwiftUI

/// 달력 머리글의 연·월을 누르면 열리는 시트. 연도를 넘기고 달을 고르면 그 달로 바로 간다.
/// 고를 수 있는 달은 달력이 넘길 수 있는 범위(`range`, `monthIndex` 값)뿐이다.
struct MonthPickerSheet: View {
    let selectedMonth: Int
    let todayMonth: Int
    let range: ClosedRange<Int>
    let onPick: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var year: Int

    init(selectedMonth: Int, todayMonth: Int, range: ClosedRange<Int>, onPick: @escaping (Int) -> Void) {
        self.selectedMonth = selectedMonth
        self.todayMonth = todayMonth
        self.range = range
        self.onPick = onPick
        _year = State(initialValue: LocalDate(firstDayOfMonthIndex: selectedMonth).year)
    }

    private var yearRange: ClosedRange<Int> {
        LocalDate(firstDayOfMonthIndex: range.lowerBound).year...LocalDate(firstDayOfMonthIndex: range.upperBound).year
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack {
                    Button("이전 해", systemImage: "chevron.left") {
                        withAnimation(.snappy) {
                            year -= 1
                        }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(year <= yearRange.lowerBound)
                    .accessibilityIdentifier("monthPicker.previousYear")
                    Spacer()
                    // 숫자에 쉼표가 붙지 않게 verbatim으로 쓴다.
                    Text(verbatim: "\(year)년")
                        .font(.title2.bold())
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(year)))
                        .accessibilityIdentifier("monthPicker.year")
                    Spacer()
                    Button("다음 해", systemImage: "chevron.right") {
                        withAnimation(.snappy) {
                            year += 1
                        }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(year >= yearRange.upperBound)
                    .accessibilityIdentifier("monthPicker.nextYear")
                }
                .font(.title3)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(1...12, id: \.self) { month in
                        monthButton(month)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("날짜로 이동")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("오늘") { pick(todayMonth) }
                }
            }
        }
    }

    private func monthButton(_ month: Int) -> some View {
        let index = year * 12 + (month - 1)
        let isSelected = index == selectedMonth
        let isThisMonth = index == todayMonth
        return Button {
            pick(index)
        } label: {
            VStack(spacing: 4) {
                Text(verbatim: "\(month)월")
                    .font(.body.weight(isSelected ? .bold : .regular))
                Circle()
                    .fill(isThisMonth ? (isSelected ? Color.white : Color.accentColor) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .disabled(!range.contains(index))
        .opacity(range.contains(index) ? 1 : 0.35)
        .accessibilityLabel(Text(verbatim: "\(year)년 \(month)월"))
        .accessibilityIdentifier("monthPicker.month.\(month)")
    }

    private func pick(_ index: Int) {
        guard range.contains(index) else { return }
        onPick(index)
        dismiss()
    }
}
