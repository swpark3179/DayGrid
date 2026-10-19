"""DayGrid 앱 아이콘(1024x1024, 알파 없는 RGB PNG)을 그린다.

사용법: python3 scripts/make_app_icon.py <출력 경로>
"""
import sys

from PIL import Image, ImageDraw

SCALE = 2  # 2배로 그린 뒤 줄여서 가장자리를 부드럽게 한다.
SIZE = 1024 * SCALE


def s(value):
    return int(value * SCALE)


def main(output_path):
    image = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(image)

    # 배경: 위에서 아래로 짙어지는 파란색
    top, bottom = (92, 124, 250), (54, 79, 199)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        color = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
        draw.line([(0, y), (SIZE, y)], fill=color)

    # 달력 카드
    card = (s(172), s(212), s(852), s(852))
    draw.rounded_rectangle(card, radius=s(96), fill=(255, 255, 255))
    # 상단 띠
    band_bottom = s(372)
    draw.rounded_rectangle((card[0], card[1], card[2], band_bottom + s(96)), radius=s(96), fill=(255, 107, 107))
    draw.rectangle((card[0], band_bottom, card[2], band_bottom + s(96)), fill=(255, 255, 255))
    # 고리
    for cx in (s(342), s(682)):
        draw.rounded_rectangle((cx - s(28), s(160), cx + s(28), s(276)), radius=s(28), fill=(236, 240, 255))

    # 날짜 칸 4열 x 3행
    cols, rows = 4, 3
    left, top_y, right, bottom_y = s(232), s(424), s(792), s(800)
    gap = s(28)
    cell_w = (right - left - gap * (cols - 1)) / cols
    cell_h = (bottom_y - top_y - gap * (rows - 1)) / rows

    def cell(col, row):
        x0 = left + col * (cell_w + gap)
        y0 = top_y + row * (cell_h + gap)
        return x0, y0, x0 + cell_w, y0 + cell_h

    for row in range(rows):
        for col in range(cols):
            draw.rounded_rectangle(cell(col, row), radius=s(22), fill=(233, 236, 245))

    # 여러 날에 걸친 일정 막대(2칸)
    x0, y0, _, y1 = cell(1, 1)
    _, _, x1, _ = cell(2, 1)
    draw.rounded_rectangle((x0, y0, x1, y1), radius=s(22), fill=(81, 207, 102))
    # 오늘 강조 칸
    draw.rounded_rectangle(cell(3, 0), radius=s(22), fill=(76, 110, 245))
    # 하루짜리 일정
    draw.rounded_rectangle(cell(0, 2), radius=s(22), fill=(252, 196, 25))

    image.resize((1024, 1024), Image.LANCZOS).save(output_path, "PNG")


if __name__ == "__main__":
    main(sys.argv[1])
