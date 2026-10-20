import DayGridCore
import SwiftUI
import WidgetKit

@main
struct DayGridWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecurringDueWidget()
    }
}

/// 잠금화면 위젯: 주기가 돌아왔는데 아직 하지 않은 반복 할일. 완료한 것은 보이지 않는다.
/// 앱이 App Group 폴더에 쓴 요약(`RecurringSnapshot`)을 읽고, 날짜마다 Core `Recurrence.isDue`로 다시 센다.
struct RecurringDueWidget: Widget {
    let kind = "RecurringDueWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecurringDueProvider()) { entry in
            RecurringDueWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(RecurringSnapshot.openURL)
        }
        .configurationDisplayName("남은 반복 할일")
        .description("주기가 돌아왔는데 아직 하지 않은 반복 할일을 보여줍니다.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct RecurringDueEntry: TimelineEntry {
    let date: Date
    /// 남은 반복 할일 제목(반복 탭 순서)
    let titles: [String]
}

/// 지금과 다음 3일의 자정에 항목을 만든다. 자정이 지나면 새 주기가 와서 목록이 바뀐다.
/// 앱에서 체크하면 앱이 요약을 다시 쓰고 타임라인을 다시 부른다.
struct RecurringDueProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecurringDueEntry {
        RecurringDueEntry(date: Date(), titles: ["물 2L 마시기", "헬스장"])
    }

    func getSnapshot(in context: Context, completion: @escaping (RecurringDueEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(entry(at: Date(), snapshot: Self.loadSnapshot()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecurringDueEntry>) -> Void) {
        let now = Date()
        let snapshot = Self.loadSnapshot()
        let today = LocalDate(now)
        let midnights = (1...3).map { today.adding(days: $0).date() }
        let entries = [entry(at: now, snapshot: snapshot)] + midnights.map { entry(at: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(midnights.last ?? now.addingTimeInterval(86_400))))
    }

    private func entry(at date: Date, snapshot: RecurringSnapshot?) -> RecurringDueEntry {
        let titles = snapshot?.pending(on: LocalDate(date)).map(\.title) ?? []
        return RecurringDueEntry(date: date, titles: titles)
    }

    private static func loadSnapshot() -> RecurringSnapshot? {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: RecurringSnapshot.appGroupID)?
            .appending(path: RecurringSnapshot.fileName),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? RecurringSnapshot.decode(data)
    }
}

struct RecurringDueWidgetView: View {
    let entry: RecurringDueEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryInline:
            inline
        default:
            rectangular
        }
    }

    private var count: Int { entry.titles.count }

    /// 머리글과 제목 최대 3개. 넘치면 2개와 "외 n개".
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label {
                Text(verbatim: "반복 할일 \(count)")
            } icon: {
                Image(systemName: "repeat")
            }
            .font(.headline)
            .widgetAccentable()
            if entry.titles.isEmpty {
                Text("남은 반복 할일 없음")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let shown = count > 3 ? Array(entry.titles.prefix(2)) : entry.titles
                ForEach(Array(shown.enumerated()), id: \.offset) { _, title in
                    Text(verbatim: "· \(title)")
                        .font(.caption)
                        .lineLimit(1)
                }
                if count > 3 {
                    Text(verbatim: "외 \(count - 2)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: count == 0 ? "checkmark" : "repeat")
                    .font(.caption)
                if count > 0 {
                    Text(verbatim: "\(count)")
                        .font(.title2.bold())
                        .widgetAccentable()
                }
            }
        }
        .accessibilityLabel(Text(verbatim: count == 0 ? "남은 반복 할일 없음" : "남은 반복 할일 \(count)개"))
    }

    private var inline: some View {
        Label {
            Text(verbatim: count == 0 ? "반복 할일 모두 완료" : "반복 할일 \(count)개 남음")
        } icon: {
            Image(systemName: "repeat")
        }
    }
}
