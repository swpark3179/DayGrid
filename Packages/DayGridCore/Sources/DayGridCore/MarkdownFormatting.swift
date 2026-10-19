import Foundation

/// 본문 편집기의 서식 툴바 버튼.
public enum MarkdownStyle: String, CaseIterable, Sendable {
    case heading
    case bold
    case italic
    case bulletList
    case checklist
    case link
    case quote
    case code
}

/// 서식 버튼을 한 번 눌렀을 때의 결과. 원래 텍스트의 `range`를 `replacement`로 바꾸고, 바꾼 뒤 `selection`을 선택한다.
/// 범위는 모두 UTF-16 단위다(`UITextView.selectedRange`와 같다).
public struct MarkdownEdit: Equatable {
    public let range: NSRange
    public let replacement: String
    public let selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    /// `text`에 이 편집을 적용한 결과.
    public func applied(to text: String) -> String {
        let units = Array(text.utf16)
        let head = MarkdownFormatter.string(units[..<range.location])
        let tail = MarkdownFormatter.string(units[(range.location + range.length)...])
        return head + replacement + tail
    }
}

/// 선택 영역에 마크다운 서식을 넣거나 뺀다.
///
/// - 굵게 `**`, 기울임 `_`, 코드 `` ` ``: 선택을 감싼다. 이미 감싸져 있으면 벗긴다. 여러 줄 코드는 ``` 블록으로 감싼다.
/// - 제목 `# `, 목록 `- `, 체크리스트 `- [ ] `, 인용 `> `: 선택이 걸친 줄 앞에 붙인다. 모든 줄에 이미 있으면 뺀다.
///   목록과 체크리스트는 서로 바꾼다. 여러 줄이면 빈 줄은 건너뛴다.
/// - 링크: `[선택](https://)`로 만들고 주소 자리를 선택한다.
public enum MarkdownFormatter {
    public static func edit(_ style: MarkdownStyle, text: String, selection: NSRange) -> MarkdownEdit {
        let units = Array(text.utf16)
        let selection = clamped(selection, count: units.count)
        switch style {
        case .bold:
            return wrap(units, selection, marker: "**")
        case .italic:
            return wrap(units, selection, marker: "_")
        case .code:
            let selected = units[selection.location..<(selection.location + selection.length)]
            return selected.contains(newline) ? fence(units, selection) : wrap(units, selection, marker: "`")
        case .link:
            return link(units, selection)
        case .heading, .bulletList, .checklist, .quote:
            return prefixLines(units, selection, style: style)
        }
    }

    // MARK: - 감싸기

    private static func wrap(_ units: [UInt16], _ selection: NSRange, marker: String) -> MarkdownEdit {
        let mark = Array(marker.utf16)
        let start = selection.location
        let end = start + selection.length
        let selected = Array(units[start..<end])

        // 선택 바깥이 표시로 둘러싸여 있으면 벗긴다.
        if start >= mark.count, end + mark.count <= units.count,
           Array(units[(start - mark.count)..<start]) == mark,
           Array(units[end..<(end + mark.count)]) == mark {
            return MarkdownEdit(
                range: NSRange(location: start - mark.count, length: selection.length + 2 * mark.count),
                replacement: string(selected[...]),
                selection: NSRange(location: start - mark.count, length: selection.length)
            )
        }
        // 선택 안쪽이 표시로 시작하고 끝나면 벗긴다.
        if selected.count >= 2 * mark.count,
           Array(selected.prefix(mark.count)) == mark,
           Array(selected.suffix(mark.count)) == mark {
            let inner = selected[mark.count..<(selected.count - mark.count)]
            return MarkdownEdit(
                range: selection,
                replacement: string(inner),
                selection: NSRange(location: start, length: inner.count)
            )
        }
        return MarkdownEdit(
            range: selection,
            replacement: marker + string(selected[...]) + marker,
            selection: NSRange(location: start + mark.count, length: selection.length)
        )
    }

    private static func fence(_ units: [UInt16], _ selection: NSRange) -> MarkdownEdit {
        let block = lineBlock(units, selection)
        let content = string(units[block])
        let opening = "```\n"
        return MarkdownEdit(
            range: NSRange(location: block.lowerBound, length: block.count),
            replacement: opening + content + "\n```",
            selection: NSRange(location: block.lowerBound + opening.utf16.count, length: block.count)
        )
    }

    private static func link(_ units: [UInt16], _ selection: NSRange) -> MarkdownEdit {
        let start = selection.location
        let selected = string(units[start..<(start + selection.length)])
        let address = "https://"
        if selection.length == 0 {
            return MarkdownEdit(
                range: selection,
                replacement: "[](\(address))",
                selection: NSRange(location: start + 1, length: 0)
            )
        }
        return MarkdownEdit(
            range: selection,
            replacement: "[\(selected)](\(address))",
            selection: NSRange(location: start + 1 + selection.length + 2, length: address.utf16.count)
        )
    }

    // MARK: - 줄 앞 표시

    private static func prefixLines(_ units: [UInt16], _ selection: NSRange, style: MarkdownStyle) -> MarkdownEdit {
        let block = lineBlock(units, selection)
        let lines = units[block].split(separator: newline, omittingEmptySubsequences: false).map { Array($0) }
        let targets = lines.count == 1 ? [0] : lines.indices.filter { !lines[$0].isEmpty }
        let removing = targets.allSatisfy { existingPrefixLength(lines[$0], style: style) != nil }
        let prefix = Array(linePrefix(for: style).utf16)

        var newLines = lines
        var cursorDelta = 0
        for index in targets {
            let line = lines[index]
            if removing {
                let length = existingPrefixLength(line, style: style) ?? 0
                newLines[index] = Array(line[length...])
                cursorDelta = -length
            } else if existingPrefixLength(line, style: style) == nil {
                let replaced = otherListPrefixLength(line, style: style) ?? 0
                newLines[index] = prefix + Array(line[replaced...])
                cursorDelta = prefix.count - replaced
            }
        }

        let joined = Array(newLines.joined(separator: [newline]))
        let newSelection = selection.length == 0
            ? NSRange(location: max(block.lowerBound, selection.location + cursorDelta), length: 0)
            : NSRange(location: block.lowerBound, length: joined.count)
        return MarkdownEdit(
            range: NSRange(location: block.lowerBound, length: block.count),
            replacement: string(joined[...]),
            selection: newSelection
        )
    }

    private static func linePrefix(for style: MarkdownStyle) -> String {
        switch style {
        case .heading: "# "
        case .bulletList: "- "
        case .checklist: "- [ ] "
        case .quote: "> "
        case .bold, .italic, .link, .code: ""
        }
    }

    /// 줄이 이미 `style` 표시로 시작하면 그 길이.
    private static func existingPrefixLength(_ line: [UInt16], style: MarkdownStyle) -> Int? {
        switch style {
        case .heading:
            let hashes = line.prefix { $0 == hashMark }.count
            guard (1...6).contains(hashes), line.count > hashes, line[hashes] == space else { return nil }
            return hashes + 1
        case .bulletList:
            guard checklistPrefixLength(line) == nil else { return nil }
            return bulletPrefixLength(line)
        case .checklist:
            return checklistPrefixLength(line)
        case .quote:
            return line.starts(with: Array("> ".utf16)) ? 2 : nil
        case .bold, .italic, .link, .code:
            return nil
        }
    }

    /// 목록 ↔ 체크리스트를 바꿀 때 지울 다른 목록 표시의 길이.
    private static func otherListPrefixLength(_ line: [UInt16], style: MarkdownStyle) -> Int? {
        switch style {
        case .bulletList: checklistPrefixLength(line)
        case .checklist: bulletPrefixLength(line)
        default: nil
        }
    }

    /// "- ", "* ", "+ "
    private static func bulletPrefixLength(_ line: [UInt16]) -> Int? {
        guard line.count >= 2, bulletMarks.contains(line[0]), line[1] == space else { return nil }
        return 2
    }

    /// "- [ ] ", "- [x] ", "- [X] "
    private static func checklistPrefixLength(_ line: [UInt16]) -> Int? {
        guard bulletPrefixLength(line) != nil, line.count >= 6,
              line[2] == openBracket, checkMarks.contains(line[3]), line[4] == closeBracket, line[5] == space
        else { return nil }
        return 6
    }

    // MARK: - 도우미

    /// 선택이 걸친 줄들의 범위(줄바꿈 제외). 선택이 다음 줄 맨 앞에서 끝나면 그 줄은 넣지 않는다.
    private static func lineBlock(_ units: [UInt16], _ selection: NSRange) -> Range<Int> {
        var lower = selection.location
        while lower > 0, units[lower - 1] != newline {
            lower -= 1
        }
        var upper = selection.length > 0 ? selection.location + selection.length - 1 : selection.location
        while upper < units.count, units[upper] != newline {
            upper += 1
        }
        return lower..<max(lower, upper)
    }

    private static func clamped(_ selection: NSRange, count: Int) -> NSRange {
        let location = min(max(0, selection.location), count)
        let length = min(max(0, selection.length), count - location)
        return NSRange(location: location, length: length)
    }

    static func string(_ units: ArraySlice<UInt16>) -> String {
        String(decoding: units, as: UTF16.self)
    }

    private static let newline = UInt16(UInt8(ascii: "\n"))
    private static let space = UInt16(UInt8(ascii: " "))
    private static let hashMark = UInt16(UInt8(ascii: "#"))
    private static let openBracket = UInt16(UInt8(ascii: "["))
    private static let closeBracket = UInt16(UInt8(ascii: "]"))
    private static let bulletMarks: Set<UInt16> = [UInt16(UInt8(ascii: "-")), UInt16(UInt8(ascii: "*")), UInt16(UInt8(ascii: "+"))]
    private static let checkMarks: Set<UInt16> = [UInt16(UInt8(ascii: " ")), UInt16(UInt8(ascii: "x")), UInt16(UInt8(ascii: "X"))]
}
