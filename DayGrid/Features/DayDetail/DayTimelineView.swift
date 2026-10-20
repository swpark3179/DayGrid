import DayGridCore
import SwiftUI

/// 하루 상세의 타임라인. 시간 일정과 할일을 시각 위치에 놓는다. 배치(범위, 열, 최소 높이)는 Core `DayTimeline`이 정한다.
///
/// - 업무 시간 밖은 옅게 칠한다.
/// - 빈 곳을 누르면 그 시각(30분 단위)에 새 일정을 연다.
///   오른쪽 여백을 비워 두어, 블록이 있는 시각에도 빈 곳을 눌러 겹치는 일정을 만들 수 있다(iOS 캘린더와 같다).
/// - 블록을 누르면 편집, 꾹 누르면 `menu`가 나온다.
struct DayTimelineView<Menu: View>: View {
    let date: LocalDate
    let timeline: DayTimeline
    let itemsByID: [UUID: Item]
    let rowsByID: [UUID: DayAgenda.Row]
    let onEdit: (Item) -> Void
    let onShowBody: (Item, String) -> Void
    let onCreate: (Int) -> Void
    @ViewBuilder let menu: (Item) -> Menu

    var body: some View {
        let height = CGFloat(timeline.rangeEnd - timeline.rangeStart) / 60 * TimelineMetrics.hourHeight
        GeometryReader { geometry in
            let gridX = TimelineMetrics.labelWidth
            let gridWidth = max(0, geometry.size.width - gridX)
            let blockAreaWidth = max(0, gridWidth - TimelineMetrics.trailingGap)
            ZStack(alignment: .topLeading) {
                ForEach(offHours, id: \.self) { range in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: gridWidth, height: y(range.upperBound, height) - y(range.lowerBound, height))
                        .offset(x: gridX, y: y(range.lowerBound, height))
                }

                // 빈 곳 누르기. 블록과 블록 안의 버튼이 위에 있으므로 먼저 받는다.
                Color.clear
                    .frame(width: gridWidth, height: height)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            onCreate(timeline.minute(atY: Double(value.location.y), height: Double(height)))
                        }
                    )
                    .offset(x: gridX)

                ForEach(timeline.hourMarks, id: \.self) { minute in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: gridWidth, height: 0.5)
                        .offset(x: gridX, y: y(minute, height))
                        .allowsHitTesting(false)
                    Text(ItemTimeText.hourLabel(minute, on: date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: gridX - 6, alignment: .trailing)
                        .offset(y: y(minute, height) - 7)
                        .allowsHitTesting(false)
                }

                ForEach(timeline.blocks) { block in
                    if let item = itemsByID[block.id], let row = rowsByID[block.id] {
                        let timeText = ItemTimeText.describe(item, row: row)
                        let columnWidth = blockAreaWidth / CGFloat(block.columnCount)
                        let top = y(block.startMinute, height)
                        // 이어지는 블록 사이에 1pt 틈을 둔다.
                        let blockHeight = max(0, y(block.endMinute, height) - top - 1)
                        TimelineBlockView(item: item, timeText: timeText, height: blockHeight) {
                            onShowBody(item, timeText)
                        }
                        .frame(width: max(0, columnWidth - 2), height: blockHeight)
                        .onTapGesture {
                            onEdit(item)
                        }
                        .contextMenu {
                            menu(item)
                        }
                        .offset(x: gridX + CGFloat(block.column) * columnWidth, y: top)
                    }
                }
            }
        }
        .frame(height: height)
        // UI 테스트가 이 요소의 크기로 누를 위치를 계산한다. 높이가 격자 높이와 같도록 여백은 바깥에 둔다.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dayDetail.timeline")
        // 맨 위·아래 시각 글자가 잘리지 않게
        .padding(.vertical, 10)
    }

    /// 범위 안의 업무 시간 밖(위, 아래).
    private var offHours: [Range<Int>] {
        [timeline.rangeStart..<timeline.workStart, timeline.workEnd..<timeline.rangeEnd].filter { !$0.isEmpty }
    }

    private func y(_ minute: Int, _ height: CGFloat) -> CGFloat {
        CGFloat(timeline.y(ofMinute: minute, height: Double(height)))
    }
}

/// 제네릭 타입에는 정적 저장 속성을 둘 수 없어서 따로 둔다.
private enum TimelineMetrics {
    static let hourHeight: CGFloat = 48
    /// 왼쪽 시각 열
    static let labelWidth: CGFloat = 48
    /// 오른쪽 빈 곳(눌러서 새 일정)
    static let trailingGap: CGFloat = 16
}

/// 타임라인의 일정 한 칸. 카테고리 색을 옅게 깔고 왼쪽에 색 막대를 둔다.
/// 할일이면 체크박스, 본문이 있으면 오른쪽 위에 본문 버튼이 있다.
private struct TimelineBlockView: View {
    let item: Item
    let timeText: String
    let height: CGFloat
    let onShowBody: () -> Void

    var body: some View {
        let color = Color(hex: item.category?.colorHex ?? CategoryPalette.uncategorizedHex)
        HStack(alignment: .top, spacing: 4) {
            if item.isTask {
                ItemMarker(item: item, compact: true)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                    .lineLimit(height >= 48 ? 2 : 1)
                if height >= 36 {
                    Text(timeText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if item.bodySummary != nil {
                Button("본문 보기", systemImage: "doc.text", action: onShowBody)
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("dayDetail.body")
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.18))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(color)
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}
