import Testing
@testable import DayGridCore

@Suite("MarkdownSummary")
struct MarkdownSummaryTests {
    @Test(arguments: [
        ("# 출장 준비\n준비물", "출장 준비"),
        ("\n\n- [ ] 여권\n- [x] 충전기", "여권"),
        ("| 항목 | 담당 |\n|---|---|", "항목 | 담당"),
        ("<mark>중요</mark> **굵게** 와 [링크](https://a.com)", "중요 굵게 와 링크"),
        ("```\nlet x = 1\n```", "let x = 1"),
        ("---\n> 인용문", "인용문"),
        ("1. 첫째", "첫째"),
        ("![사진](a.png)", "사진"),
        ("<br>\n두번째 줄", "두번째 줄"),
        ("> - [x] 끝", "끝"),
        ("|:---|---:|\n| a |", "a"),
    ])
    func firstLineWithoutMarkdown(markdown: String, expected: String) {
        #expect(MarkdownSummary.firstLine(of: markdown) == expected)
    }

    @Test func emptyBodyHasNoSummary() {
        #expect(MarkdownSummary.firstLine(of: "") == nil)
        #expect(MarkdownSummary.firstLine(of: "   \n\n") == nil)
        #expect(MarkdownSummary.firstLine(of: "<br>\n---") == nil)
    }
}
