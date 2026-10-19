import DayGridCore
import Foundation
import SwiftData

/// UI 테스트와 스크린샷용 샘플 일정. 날짜는 모두 `today` 기준 상대값이다(기준일 2026-10-19).
enum SampleData {
    static func insert(into context: ModelContext, today: LocalDate, timeZone: TimeZone = .current) throws {
        let categories = try context.fetch(FetchDescriptor<ItemCategory>())
        func category(_ name: String) -> ItemCategory? {
            categories.first { $0.name == name }
        }

        func allDay(_ title: String, _ categoryName: String, _ startOffset: Int, _ endOffset: Int? = nil) {
            let item = Item(title: title, category: category(categoryName))
            item.scheduleAllDay(from: today.adding(days: startOffset), through: today.adding(days: endOffset ?? startOffset))
            context.insert(item)
        }

        func timed(_ title: String, _ categoryName: String, _ offset: Int, _ hour: Int, _ minute: Int = 0, hours: Double = 1) {
            let item = Item(title: title, category: category(categoryName))
            let start = today.adding(days: offset).date(hour: hour, minute: minute, in: timeZone)
            item.scheduleTimed(start: start, end: start.addingTimeInterval(hours * 3600), timeZone: timeZone)
            context.insert(item)
        }

        allDay("가족 여행", "가족", -18, -16)      // 10/1–10/3
        timed("치과 예약", "건강", -14, 14)          // 10/5
        allDay("스프린트", "업무", -7, -3)          // 10/12–10/16
        timed("팀 회식", "업무", -5, 19, hours: 3)   // 10/14
        timed("아침 운동", "건강", -4, 7)            // 10/15
        timed("주간 회의", "업무", 0, 10)            // 10/19 (오늘)
        timed("점심 약속", "개인", 0, 12, 30)
        timed("은행 업무", "기타", 0, 16)
        timed("독서 모임", "개인", 3, 20)            // 10/22
        allDay("캠핑", "가족", 5, 6)                // 10/24–10/25
        allDay("출장", "업무", 9, 15)               // 10/28–11/3
        allDay("보고서 제출", "업무", 11)            // 10/30: "+N" 확인용
        timed("세미나", "업무", 11, 9)
        timed("병원", "건강", 11, 15)
        timed("저녁 약속", "개인", 11, 19)
        try context.save()
    }
}
