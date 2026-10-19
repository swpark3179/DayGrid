import Foundation

/// 목록 행에 보일 본문 요약.
public enum MarkdownSummary {
    /// 내용이 있는 첫 줄을 기호 없이 돌려준다. 내용이 없으면 `nil`.
    ///
    /// 줄 앞의 제목·인용·목록·번호·체크 표시, HTML 태그, 강조 기호(`**`, `__`, `~~`, `*`, `` ` ``)를 지우고,
    /// 링크와 이미지는 글자만 남긴다. 코드 블록의 ``` 줄, 표 구분선, 가로줄은 건너뛴다.
    public static func firstLine(of markdown: String) -> String? {
        var isInFence = false
        for rawLine in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                isInFence.toggle()
                continue
            }
            if isInFence {
                if !line.isEmpty { return line }
                continue
            }
            if let text = plainText(of: line), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    /// 한 줄에서 마크다운 기호를 뺀 글자. 표 구분선이나 가로줄이면 `nil`.
    static func plainText(of line: String) -> String? {
        if line.wholeMatch(of: #/\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?/#) != nil
            || line.wholeMatch(of: #/([-*_]\s*){3,}/#) != nil {
            return nil
        }
        var text = line
        while let marker = text.prefixMatch(of: #/#{1,6}\s+|>\s?|[-*+]\s+|\d+[.\)]\s+|\[[ xX]\]\s+/#) {
            text.removeSubrange(marker.range)
        }
        text = text
            .replacing(#/!\[([^\]]*)\]\([^\)]*\)/#) { $0.1 }
            .replacing(#/\[([^\]]*)\]\([^\)]*\)/#) { $0.1 }
            .replacing(#/<[^>]*>/#, with: "")
            .replacing(#/\*\*|__|~~|`|\*/#, with: "")
        if text.hasPrefix("|") {
            text.removeFirst()
        }
        if text.hasSuffix("|") {
            text.removeLast()
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
