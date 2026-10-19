import Foundation
import Testing
@testable import DayGridCore

private func range(_ location: Int, _ length: Int) -> NSRange {
    NSRange(location: location, length: length)
}

/// `style`을 적용한 결과 텍스트와 선택 범위.
private func format(_ style: MarkdownStyle, _ text: String, _ selection: NSRange) -> (text: String, selection: NSRange) {
    let edit = MarkdownFormatter.edit(style, text: text, selection: selection)
    return (edit.applied(to: text), edit.selection)
}

@Suite("MarkdownFormatter 감싸기")
struct MarkdownWrapTests {
    @Test func boldWithoutSelectionPutsTheCursorBetweenMarkers() {
        let result = format(.bold, "할일 ", range(3, 0))
        #expect(result.text == "할일 ****")
        #expect(result.selection == range(5, 0))
    }

    @Test func boldWrapsAndUnwrapsTheSelection() {
        let wrapped = format(.bold, "책 반납", range(2, 2))
        #expect(wrapped.text == "책 **반납**")
        #expect(wrapped.selection == range(4, 2))

        let unwrapped = format(.bold, wrapped.text, wrapped.selection)
        #expect(unwrapped.text == "책 반납")
        #expect(unwrapped.selection == range(2, 2))

        let selectedWithMarkers = format(.bold, "**반납**", range(0, 6))
        #expect(selectedWithMarkers.text == "반납")
        #expect(selectedWithMarkers.selection == range(0, 2))
    }

    @Test func rangesAreUTF16() {
        let edit = MarkdownFormatter.edit(.bold, text: "👍 좋아", selection: range(3, 2))
        #expect(edit.range == range(3, 2))
        #expect(edit.replacement == "**좋아**")
        #expect(edit.applied(to: "👍 좋아") == "👍 **좋아**")
        #expect(edit.selection == range(5, 2))
    }

    @Test func selectionOutsideTheTextIsClamped() {
        let result = format(.bold, "ab", range(5, 3))
        #expect(result.text == "ab****")
        #expect(result.selection == range(4, 0))
    }

    @Test func italicUsesUnderscores() {
        let result = format(.italic, "a b", range(2, 1))
        #expect(result.text == "a _b_")
        #expect(result.selection == range(3, 1))
    }

    @Test func codeIsInlineOnOneLineAndFencedOnMany() {
        let inline = format(.code, "run ls", range(4, 2))
        #expect(inline.text == "run `ls`")
        #expect(inline.selection == range(5, 2))

        let fenced = format(.code, "a\nb\nc", range(2, 3))
        #expect(fenced.text == "a\n```\nb\nc\n```")
        #expect(fenced.selection == range(6, 3))
    }

    @Test func linkSelectsTheAddress() {
        let withText = format(.link, "문서 보기", range(0, 2))
        #expect(withText.text == "[문서](https://) 보기")
        #expect(withText.selection == range(5, 8))

        let empty = format(.link, "", range(0, 0))
        #expect(empty.text == "[](https://)")
        #expect(empty.selection == range(1, 0))
    }
}

@Suite("MarkdownFormatter 줄 앞 표시")
struct MarkdownLinePrefixTests {
    @Test func headingToggles() {
        let added = format(.heading, "제목", range(1, 0))
        #expect(added.text == "# 제목")
        #expect(added.selection == range(3, 0))

        let removed = format(.heading, "# 제목", range(3, 0))
        #expect(removed.text == "제목")
        #expect(removed.selection == range(1, 0))

        let anyLevel = format(.heading, "## 제목", range(0, 0))
        #expect(anyLevel.text == "제목")
        #expect(anyLevel.selection == range(0, 0))
    }

    @Test func onlyTheCursorLineChanges() {
        let edit = MarkdownFormatter.edit(.heading, text: "a\nbc\nd", selection: range(3, 0))
        #expect(edit.range == range(2, 2))
        #expect(edit.replacement == "# bc")
        #expect(edit.selection == range(5, 0))
    }

    @Test func bulletListSkipsEmptyLinesAndSelectsTheBlock() {
        let result = format(.bulletList, "a\n\nb", range(0, 4))
        #expect(result.text == "- a\n\n- b")
        #expect(result.selection == range(0, 8))
    }

    @Test func bulletListIsRemovedWhenEveryLineHasIt() {
        let removed = format(.bulletList, "- a\n- b", range(0, 7))
        #expect(removed.text == "a\nb")
        #expect(removed.selection == range(0, 3))

        let mixed = format(.bulletList, "- a\nb", range(0, 5))
        #expect(mixed.text == "- a\n- b")
        #expect(mixed.selection == range(0, 7))
    }

    @Test func bulletOnAnEmptyText() {
        let result = format(.bulletList, "", range(0, 0))
        #expect(result.text == "- ")
        #expect(result.selection == range(2, 0))
    }

    @Test func bulletAndChecklistSwitch() {
        let toChecklist = format(.checklist, "- 여권", range(4, 0))
        #expect(toChecklist.text == "- [ ] 여권")
        #expect(toChecklist.selection == range(8, 0))

        let toBullet = format(.bulletList, "- [x] 충전기", range(9, 0))
        #expect(toBullet.text == "- 충전기")
        #expect(toBullet.selection == range(5, 0))

        let removed = format(.checklist, "- [ ] 여권", range(8, 0))
        #expect(removed.text == "여권")
        #expect(removed.selection == range(2, 0))
    }

    @Test func selectionEndingAtTheNextLineStartLeavesThatLine() {
        let result = format(.quote, "a\nb\n", range(0, 2))
        #expect(result.text == "> a\nb\n")
        #expect(result.selection == range(0, 3))
    }
}
