import Testing
@testable import DayGridCore

@Suite("MarkdownTaskList")
struct MarkdownTaskListTests {
    private let trip = """
        # 부산 출장
        - [x] 기차표 예매
        - [ ] 발표 자료 출력
        - [ ] 명함 챙기기
        """

    @Test func findsTasksInDocumentOrder() {
        let tasks = MarkdownTaskList.tasks(in: trip)
        #expect(tasks.map(\.line) == [1, 2, 3])
        #expect(tasks.map(\.isChecked) == [true, false, false])
    }

    @Test func togglingChangesOnlyThatCheck() {
        let toggled = MarkdownTaskList.toggle(at: 1, in: trip)
        #expect(toggled == """
            # 부산 출장
            - [x] 기차표 예매
            - [x] 발표 자료 출력
            - [ ] 명함 챙기기
            """)
        #expect(MarkdownTaskList.toggle(at: 0, in: trip)?.contains("- [ ] 기차표 예매") == true)
        // 두 번 뒤집으면 원래대로
        #expect(toggled.flatMap { MarkdownTaskList.toggle(at: 1, in: $0) } == trip)
    }

    @Test func upperCaseXCountsAsChecked() {
        #expect(MarkdownTaskList.toggle(at: 0, in: "- [X] 끝") == "- [ ] 끝")
    }

    @Test func acceptsOtherListMarkersNestingAndQuotes() {
        let text = """
            * [ ] 별표
            + [x] 더하기
            1. [ ] 번호
            2) [ ] 괄호 번호
              - [ ] 들여쓴 하위 목록
            > - [ ] 인용 안
            - - [ ] 한 줄에 겹친 목록
            """
        #expect(MarkdownTaskList.tasks(in: text).map(\.line) == [0, 1, 2, 3, 4, 5, 6])
        #expect(MarkdownTaskList.toggle(at: 5, in: text)?.contains("> - [x] 인용 안") == true)
    }

    @Test func ignoresLinesThatAreNotTasks() {
        let text = """
            [ ] 목록 표시가 없다
            - [ ]
            - [ ]\u{0020}\u{0020}
            -[ ] 공백이 없다
            - [y] 다른 글자
            - [ ]붙어 있다
            * * *
            """
        #expect(MarkdownTaskList.tasks(in: text).isEmpty)
    }

    @Test func nbspAfterTheBracketCounts() {
        #expect(MarkdownTaskList.tasks(in: "- [ ]\u{00A0}할일").count == 1)
    }

    @Test func skipsFencedCode() {
        let text = """
            - [ ] 첫째
            ```markdown
            - [ ] 코드 안
            ```
            ~~~~
            - [x] 물결 펜스 안
            ```
            - [x] 짧은 펜스는 닫지 못한다
            ~~~~
            - [ ] 둘째
            """
        let tasks = MarkdownTaskList.tasks(in: text)
        #expect(tasks.map(\.line) == [0, 9])
        #expect(MarkdownTaskList.toggle(at: 1, in: text)?.hasSuffix("- [x] 둘째") == true)
    }

    @Test func outOfRangeIndexReturnsNil() {
        #expect(MarkdownTaskList.toggle(at: 3, in: trip) == nil)
        #expect(MarkdownTaskList.toggle(at: -1, in: trip) == nil)
        #expect(MarkdownTaskList.toggle(at: 0, in: "") == nil)
    }

    @Test func keepsWindowsLineEndings() {
        let text = "- [ ] 하나\r\n- [ ] 둘\r\n"
        #expect(MarkdownTaskList.toggle(at: 1, in: text) == "- [ ] 하나\r\n- [x] 둘\r\n")
    }
}
