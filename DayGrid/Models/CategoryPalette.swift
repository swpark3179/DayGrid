import SwiftUI

/// 카테고리 색 프리셋. 모두 흰 글씨가 읽히는 진한 색이다.
enum CategoryPalette {
    struct Swatch: Identifiable, Sendable {
        let name: String
        let hex: String

        var id: String { hex }
    }

    static let swatches: [Swatch] = [
        Swatch(name: "남색", hex: "#4263EB"),
        Swatch(name: "파랑", hex: "#1C7ED6"),
        Swatch(name: "청록", hex: "#0C8599"),
        Swatch(name: "초록", hex: "#2F9E44"),
        Swatch(name: "주황", hex: "#E8590C"),
        Swatch(name: "빨강", hex: "#E03131"),
        Swatch(name: "분홍", hex: "#D6336C"),
        Swatch(name: "자주", hex: "#AE3EC9"),
        Swatch(name: "보라", hex: "#7048E8"),
        Swatch(name: "회색", hex: "#495057"),
    ]

    /// 카테고리가 없는 일정의 색.
    static let uncategorizedHex = "#868E96"
}

extension Color {
    /// "#RRGGBB" 형식. 읽을 수 없으면 카테고리 없음 색을 쓴다.
    init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = (digits.count == 6 ? UInt32(digits, radix: 16) : nil) ?? 0x868E96
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
