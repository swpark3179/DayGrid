"""App Store 스크린샷을 만든다: 앱 화면을 기기 모양 틀에 넣고 위에 문구를 붙인다.

사용법:
  python3 scripts/appstore/compose_screenshots.py \
      --config appstore/screenshots.json --raw <앱 화면 PNG 폴더> --fonts <글꼴 폴더> --out <출력 폴더>

- 앱 화면은 UI 테스트(`AppStoreScreenshotTests`)가 남긴 `NN-이름.png`다. 설정의 `raw` 이름으로 찾는다.
- 글꼴은 Pretendard(OFL) Bold·Medium을 쓴다(`Pretendard-Bold.otf`, `Pretendard-Medium.otf`).
  워크플로가 jsDelivr에서 받아 해시를 확인한다.
- 출력
  - `framed/<크기>/NN-이름.png`: 문구와 기기 틀을 넣은 스크린샷(올리는 용도)
  - `plain/<크기>/NN-이름.png`: 앱 화면만 그 크기로 맞춘 것
  - `contact-sheet.png`: 한눈에 보는 미리보기(올리지 않는다)
- App Store는 알파 채널이 있는 이미지를 받지 않으므로 모두 RGB로 저장한다.
"""
import argparse
import json
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

THEMES = {
    # 앱 아이콘과 같은 파랑(scripts/make_app_icon.py)
    "light": {"top": (92, 124, 250), "bottom": (48, 70, 186), "grid": (255, 255, 255, 20), "subtitle": (232, 237, 255)},
    "dark": {"top": (38, 46, 92), "bottom": (10, 12, 28), "grid": (255, 255, 255, 14), "subtitle": (200, 208, 235)},
}
SUPERSAMPLE = 4


def load_font(folder, weight, size):
    path = pathlib.Path(folder) / f"Pretendard-{weight}.otf"
    if not path.exists():
        sys.exit(f"글꼴이 없습니다: {path}")
    return ImageFont.truetype(str(path), size)


def smooth_mask(size, box, radius):
    """가장자리가 부드러운 둥근 사각형 마스크(크게 그린 뒤 줄인다)."""
    width, height = size
    big = Image.new("L", (width * SUPERSAMPLE, height * SUPERSAMPLE), 0)
    scaled = [round(v * SUPERSAMPLE) for v in box]
    ImageDraw.Draw(big).rounded_rectangle(scaled, radius=round(radius * SUPERSAMPLE), fill=255)
    return big.resize(size, Image.LANCZOS)


def background(width, height, theme):
    colors = THEMES[theme]
    image = Image.new("RGB", (width, height))
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / (height - 1)
        color = tuple(round(a + (b - a) * t) for a, b in zip(colors["top"], colors["bottom"]))
        draw.line([(0, y), (width, y)], fill=color)

    # 이름(DayGrid)에 맞춘 옅은 격자. 위쪽에서만 보이고 아래로 갈수록 사라진다.
    grid = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    grid_draw = ImageDraw.Draw(grid)
    step = width / 7
    line = max(2, round(width / 660))
    for i in range(1, 7):
        x = round(i * step)
        grid_draw.line([(x, 0), (x, height)], fill=colors["grid"], width=line)
    y = step
    while y < height:
        grid_draw.line([(0, round(y)), (width, round(y))], fill=colors["grid"], width=line)
        y += step
    fade = Image.linear_gradient("L").resize((width, height))
    fade = fade.point(lambda v: max(0, 255 - v * 2))
    alpha = Image.composite(grid.getchannel("A"), Image.new("L", (width, height), 0), fade)
    grid.putalpha(alpha)
    image.paste(grid, (0, 0), grid)
    return image


def draw_text_block(image, title, subtitle, fonts_dir, theme, area_top, area_bottom):
    width = image.width
    draw = ImageDraw.Draw(image)
    max_width = width * 0.88

    title_size = round(width * 0.074)
    title_lines = title.split("\n")
    while True:
        title_font = load_font(fonts_dir, "Bold", title_size)
        if all(draw.textlength(line, font=title_font) <= max_width for line in title_lines) or title_size < 40:
            break
        title_size -= 2
    subtitle_size = round(width * 0.039)
    while True:
        subtitle_font = load_font(fonts_dir, "Medium", subtitle_size)
        if draw.textlength(subtitle, font=subtitle_font) <= max_width or subtitle_size < 28:
            break
        subtitle_size -= 2

    title_line_height = round(title_size * 1.22)
    subtitle_height = round(subtitle_size * 1.3)
    gap = round(width * 0.03)
    block_height = title_line_height * len(title_lines) + gap + subtitle_height
    y = area_top + (area_bottom - area_top - block_height) / 2

    for line in title_lines:
        draw.text((width / 2, y), line, font=title_font, fill=(255, 255, 255), anchor="mt")
        y += title_line_height
    y += gap
    draw.text((width / 2, y), subtitle, font=subtitle_font, fill=THEMES[theme]["subtitle"], anchor="mt")


def paste_device(image, screen, top, bottom):
    """앱 화면을 기기 틀(베젤, 다이내믹 아일랜드, 그림자)에 넣어 [top, bottom] 사이 가운데에 놓는다."""
    width, height = image.size
    bezel = width * 0.021
    device_height = bottom - top
    screen_height = device_height - 2 * bezel
    screen_width = screen_height * screen.width / screen.height
    if screen_width + 2 * bezel > width * 0.86:
        screen_width = width * 0.86 - 2 * bezel
        screen_height = screen_width * screen.height / screen.width
        device_height = screen_height + 2 * bezel
    device_width = screen_width + 2 * bezel
    left = (width - device_width) / 2
    screen_radius = screen_width * 0.125
    device_radius = screen_radius + bezel
    device_box = (left, top, left + device_width, top + device_height)

    # 그림자
    shadow = Image.new("L", image.size, 0)
    offset = height * 0.012
    ImageDraw.Draw(shadow).rounded_rectangle(
        (device_box[0], device_box[1] + offset, device_box[2], device_box[3] + offset), radius=device_radius, fill=110
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(width * 0.03))
    image.paste(Image.new("RGB", image.size, (8, 10, 30)), (0, 0), shadow)

    # 테두리(금속 느낌의 얇은 선)와 베젤
    rim = width * 0.004
    image.paste((92, 96, 110), (0, 0), smooth_mask(image.size, device_box, device_radius))
    inner = (device_box[0] + rim, device_box[1] + rim, device_box[2] - rim, device_box[3] - rim)
    image.paste((12, 12, 16), (0, 0), smooth_mask(image.size, inner, device_radius - rim))

    # 화면
    screen_box = (left + bezel, top + bezel, left + bezel + screen_width, top + bezel + screen_height)
    box = tuple(round(v) for v in screen_box)
    size = (box[2] - box[0], box[3] - box[1])
    resized = screen.convert("RGB").resize(size, Image.LANCZOS)
    layer = Image.new("RGB", image.size)
    layer.paste(resized, box[:2])
    image.paste(layer, (0, 0), smooth_mask(image.size, screen_box, screen_radius))

    # 다이내믹 아일랜드
    island_width = screen_width * 0.285
    island_height = screen_width * 0.083
    island_top = screen_box[1] + screen_width * 0.026
    island_left = left + (device_width - island_width) / 2
    island_box = (island_left, island_top, island_left + island_width, island_top + island_height)
    image.paste((0, 0, 0), (0, 0), smooth_mask(image.size, island_box, island_height / 2))


def compose(screen, entry, size, fonts_dir):
    width, height = size["width"], size["height"]
    theme = entry.get("theme", "light")
    image = background(width, height, theme)
    draw_text_block(image, entry["title"], entry["subtitle"], fonts_dir, theme, height * 0.045, height * 0.205)
    paste_device(image, screen, height * 0.225, height * 0.975)
    return image


def contact_sheet(paths, out_path, columns=5, thumb_width=330):
    images = [Image.open(p) for p in paths]
    if not images:
        return
    thumb_height = round(thumb_width * images[0].height / images[0].width)
    rows = (len(images) + columns - 1) // columns
    pad = 16
    sheet = Image.new("RGB", (columns * (thumb_width + pad) + pad, rows * (thumb_height + pad) + pad), (245, 246, 250))
    for i, image in enumerate(images):
        thumb = image.resize((thumb_width, thumb_height), Image.LANCZOS)
        sheet.paste(thumb, (pad + (i % columns) * (thumb_width + pad), pad + (i // columns) * (thumb_height + pad)))
    sheet.save(out_path, optimize=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", required=True)
    parser.add_argument("--raw", required=True, help="앱 화면 PNG 폴더(NN-이름.png)")
    parser.add_argument("--fonts", required=True, help="Pretendard-Bold.otf, Pretendard-Medium.otf가 있는 폴더")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    config = json.loads(pathlib.Path(args.config).read_text(encoding="utf-8"))
    raw_dir, out_dir = pathlib.Path(args.raw), pathlib.Path(args.out)
    missing = [e["raw"] for e in config["screens"] if not (raw_dir / f"{e['raw']}.png").exists()]
    if missing:
        print(f"::warning::앱 화면이 없어 건너뜁니다: {', '.join(missing)}")

    framed_for_sheet = []
    for size in config["sizes"]:
        framed_dir = out_dir / "framed" / size["name"]
        plain_dir = out_dir / "plain" / size["name"]
        framed_dir.mkdir(parents=True, exist_ok=True)
        plain_dir.mkdir(parents=True, exist_ok=True)
        for entry in config["screens"]:
            source = raw_dir / f"{entry['raw']}.png"
            if not source.exists():
                continue
            screen = Image.open(source).convert("RGB")
            framed = compose(screen, entry, size, args.fonts)
            framed_path = framed_dir / f"{entry['raw']}.png"
            framed.save(framed_path, optimize=True)
            screen.resize((size["width"], size["height"]), Image.LANCZOS).save(plain_dir / f"{entry['raw']}.png", optimize=True)
            if size is config["sizes"][0]:
                framed_for_sheet.append(framed_path)
            print(f"{framed_path} ({size['width']}x{size['height']})")

    contact_sheet(framed_for_sheet, out_dir / "contact-sheet.png")
    if not framed_for_sheet:
        sys.exit("만든 스크린샷이 없습니다")


if __name__ == "__main__":
    main()
