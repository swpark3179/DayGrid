/// 본문의 체크리스트(`- [ ] 할일`, `- [x] 끝낸 일`)를 찾고 하나씩 뒤집는다.
///
/// 읽기 화면의 미리보기(`preview.js`)는 체크박스를 문서 순서대로 0, 1, 2…로 번호 매긴다.
/// 같은 순서가 되도록 `preview.js`의 규칙을 따른다.
/// - 목록 표시(`-`, `*`, `+`, `1.`, `1)`)와 공백 뒤에 `[ ]`·`[x]`·`[X]`가 오고, 그 뒤에 공백(또는 NBSP)과 글자가 온다.
/// - 인용(`>`) 안의 목록도 센다.
/// - 펜스 코드 블록(``` 또는 ~~~) 안은 세지 않는다.
public enum MarkdownTaskList {
    public struct Task: Hashable, Sendable {
        /// 0부터 센 줄 번호
        public let line: Int
        public let isChecked: Bool
    }

    public static func tasks(in text: String) -> [Task] {
        scan(lines(of: text)).map { Task(line: $0.line, isChecked: $0.isChecked) }
    }

    /// `index`번째(0부터) 체크를 뒤집은 본문. 그런 체크가 없으면 `nil`.
    public static func toggle(at index: Int, in text: String) -> String? {
        var lines = lines(of: text)
        let found = scan(lines)
        guard found.indices.contains(index) else { return nil }
        let target = found[index]
        lines[target.line][target.offset] = target.isChecked ? " " : "x"
        var view = String.UnicodeScalarView()
        for (number, line) in lines.enumerated() {
            if number > 0 {
                view.append("\n")
            }
            view.append(contentsOf: line)
        }
        return String(view)
    }

    // MARK: - 찾기

    private struct Found {
        let line: Int
        /// 체크 문자(` `/`x`/`X`)의 유니코드 스칼라 위치
        let offset: Int
        let isChecked: Bool
    }

    /// 줄 단위 유니코드 스칼라. 문자(Character) 단위로 나누면 "\r\n"이 한 글자라 줄이 나뉘지 않는다.
    private static func lines(of text: String) -> [[Unicode.Scalar]] {
        Array(text.unicodeScalars).split(separator: "\n", omittingEmptySubsequences: false).map(Array.init)
    }

    private static func scan(_ lines: [[Unicode.Scalar]]) -> [Found] {
        var found: [Found] = []
        var openFence: (character: Unicode.Scalar, length: Int)?
        for (number, scalars) in lines.enumerated() {
            let start = skipIndentAndQuotes(scalars, from: 0)
            if let fence = fence(in: scalars, at: start) {
                if let open = openFence {
                    if fence.character == open.character, fence.length >= open.length, fence.isBare {
                        openFence = nil
                    }
                } else {
                    openFence = (fence.character, fence.length)
                }
                continue
            }
            guard openFence == nil, let offset = checkOffset(scalars, from: start) else { continue }
            found.append(Found(line: number, offset: offset, isChecked: scalars[offset] != " "))
        }
        return found
    }

    private static func skipIndentAndQuotes(_ scalars: [Unicode.Scalar], from index: Int) -> Int {
        var i = index
        while i < scalars.count, scalars[i] == " " || scalars[i] == "\t" || scalars[i] == ">" {
            i += 1
        }
        return i
    }

    /// 펜스(``` 또는 ~~~ 세 개 이상). `isBare`는 펜스 뒤에 공백만 있는지(닫는 펜스의 조건).
    private static func fence(in scalars: [Unicode.Scalar], at start: Int) -> (character: Unicode.Scalar, length: Int, isBare: Bool)? {
        guard start < scalars.count, scalars[start] == "`" || scalars[start] == "~" else { return nil }
        let character = scalars[start]
        var end = start
        while end < scalars.count, scalars[end] == character {
            end += 1
        }
        guard end - start >= 3 else { return nil }
        let isBare = scalars[end...].allSatisfy { $0 == " " || $0 == "\t" || $0 == "\r" }
        return (character, end - start, isBare)
    }

    /// 목록 표시 뒤의 `[ ]`에서 체크 문자의 위치. 체크리스트 줄이 아니면 `nil`.
    private static func checkOffset(_ scalars: [Unicode.Scalar], from start: Int) -> Int? {
        var i = start
        var sawMarker = false
        // "- - [ ] 할일"처럼 목록 안의 목록이 한 줄에 올 수 있다.
        while let next = afterListMarker(scalars, at: i) {
            sawMarker = true
            i = next
        }
        guard sawMarker, i + 3 < scalars.count else { return nil }
        guard scalars[i] == "[", scalars[i + 2] == "]", [" ", "x", "X"].contains(scalars[i + 1]) else { return nil }
        guard scalars[i + 3] == " " || scalars[i + 3] == "\u{00A0}" else { return nil }
        guard scalars[(i + 4)...].contains(where: { !$0.properties.isWhitespace }) else { return nil }
        return i + 1
    }

    /// `index`에 목록 표시와 공백이 있으면 그다음 위치.
    private static func afterListMarker(_ scalars: [Unicode.Scalar], at index: Int) -> Int? {
        guard index < scalars.count else { return nil }
        var i = index
        if scalars[i] == "-" || scalars[i] == "*" || scalars[i] == "+" {
            i += 1
        } else {
            let digitsStart = i
            while i < scalars.count, i - digitsStart < 9, ("0"..."9").contains(Character(scalars[i])) {
                i += 1
            }
            guard i > digitsStart, i < scalars.count, scalars[i] == "." || scalars[i] == ")" else { return nil }
            i += 1
        }
        let spacesStart = i
        while i < scalars.count, scalars[i] == " " || scalars[i] == "\t" {
            i += 1
        }
        return i > spacesStart ? i : nil
    }
}
