import DayGridCore
import Foundation
import SwiftData

/// UI 테스트와 스크린샷용 샘플 일정. 날짜는 모두 `today` 기준 상대값이다(기준일 2026-10-19).
/// 날짜가 있는 일정 15개와 "나중에" 목록 항목 5개(그중 완료 1개, 미뤄 둔 일정 1개)를 넣는다.
/// 생일 4명(30일 안에 3명, 음력 1명), 개인 휴일 1개, 반복 할일 3개(완료 기록 포함)도 넣는다.
enum SampleData {
    static func insert(into context: ModelContext, today: LocalDate, timeZone: TimeZone = .current) throws {
        let categories = try context.fetch(FetchDescriptor<ItemCategory>())
        func category(_ name: String) -> ItemCategory? {
            categories.first { $0.name == name }
        }

        func allDay(_ title: String, _ categoryName: String, _ startOffset: Int, _ endOffset: Int? = nil, body: String? = nil) {
            let item = Item(title: title, category: category(categoryName))
            item.scheduleAllDay(from: today.adding(days: startOffset), through: today.adding(days: endOffset ?? startOffset))
            item.body = body
            context.insert(item)
        }

        func timed(_ title: String, _ categoryName: String, _ offset: Int, _ hour: Int, _ minute: Int = 0, hours: Double = 1, body: String? = nil) {
            let item = Item(title: title, category: category(categoryName))
            let start = today.adding(days: offset).date(hour: hour, minute: minute, in: timeZone)
            item.scheduleTimed(start: start, end: start.addingTimeInterval(hours * 3600), timeZone: timeZone)
            item.body = body
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
        allDay("출장", "업무", 9, 15, body: tripBody) // 10/28–11/3
        allDay("보고서 제출", "업무", 11)            // 10/30: "+N" 확인용
        timed("세미나", "업무", 11, 9, body: "- [ ] 발표 자료 출력\n- [ ] 명함 챙기기") // 타임라인의 본문 버튼 확인용
        timed("병원", "건강", 11, 15)
        timed("저녁 약속", "개인", 11, 19)

        func inbox(_ title: String, _ categoryName: String, order: Double, isDone: Bool = false, body: String? = nil) {
            let item = Item(title: title, isTask: true, category: category(categoryName))
            item.inboxOrder = order
            item.body = body
            if isDone {
                item.completedAt = today.date(hour: 9, in: timeZone)
            }
            context.insert(item)
        }

        inbox("책 반납하기", "개인", order: 0)
        inbox("선물 고르기", "가족", order: 1, body: "- [x] 엄마: 스카프\n- [ ] 아빠: 책\n- [ ] 동생: 이어폰")
        inbox("건강검진 예약", "건강", order: 2)
        let cleaning = Item(title: "대청소", category: category("가족"))
        cleaning.scheduleAllDay(from: today.adding(days: 12), through: today.adding(days: 13))
        cleaning.moveToInbox(order: 3, timeZone: timeZone)
        context.insert(cleaning)
        inbox("우산 사기", "기타", order: 4, isDone: true)

        func person(_ name: String, _ offset: Int, lunar: Bool = false, birthYear: Int = 0) {
            let date = today.adding(days: offset)
            let birthday: Birthday
            if lunar, let lunarDate = KoreanLunarCalendar.lunarDate(from: date) {
                birthday = Birthday(month: lunarDate.month, day: lunarDate.day, isLunar: true, isLeapMonth: lunarDate.isLeapMonth)
            } else {
                birthday = Birthday(month: date.month, day: date.day)
            }
            context.insert(Person(name: name, birthday: birthday, birthYear: birthYear))
        }

        person("김민수", 3, birthYear: 1990)        // 10/22
        person("엄마", 8, lunar: true)             // 10/27 (음력 9/17)
        person("아빠", 20)                          // 11/8
        person("이지은", 66)                        // 12/24: 30일 밖
        context.insert(PersonalHoliday(name: "회사 창립기념일", from: today.adding(days: -3), through: today.adding(days: -3)))

        func recurring(_ title: String, _ rule: RecurrenceRule, startOffset: Int, done: [(cycle: Int, on: Int)]) {
            let task = RecurringTask(title: title, rule: rule, startDay: today.adding(days: startOffset))
            context.insert(task)
            for entry in done {
                let completion = RecurrenceCompletion(cycleStart: today.adding(days: entry.cycle), completedOn: today.adding(days: entry.on))
                context.insert(completion)
                completion.task = task
            }
        }

        recurring("물 2L 마시기", .daily, startOffset: -14, done: [(-7, -7), (-6, -6), (-4, -4), (-3, -3), (-1, -1)])
        recurring("헬스장", .weekly(weekdays: [2, 4, 6]), startOffset: -18, done: [(-17, -17), (-14, -13), (-10, -10)]) // 월·수·금
        recurring("관리비 납부", .monthly(day: 25), startOffset: -48, done: [(-24, -23)])                              // 9/25 주기, 9/26 납부
        try context.save()
    }

    /// 본문 미리보기 스크린샷용: 제목, 표, HTML, 체크리스트, 링크가 들어 있다.
    private static let tripBody = """
        # 부산 출장
        <mark>10월 28일 09:00</mark> 서울역 출발, 숙소는 **해운대**.

        | 날짜 | 일정 |
        |---|---|
        | 10/28 | 고객사 미팅 |
        | 10/29 | 공장 방문 |

        - [x] 기차표 예매
        - [ ] 발표 자료 출력
        - [ ] 명함 챙기기

        > 비용은 [경비 시스템](https://example.com)에 올린다.
        """
}
