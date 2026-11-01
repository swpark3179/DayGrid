"""App Store 등록 문구(`appstore/metadata`)의 길이와 형식을 확인한다.

사용법: python3 scripts/appstore/check_metadata.py [저장소 루트]

- 글자 수 한도: 이름·부제 30, 프로모션 텍스트 170, 키워드 100, 설명 4000
- 키워드: 쉼표로 나누고, 쉼표 앞뒤에 빈칸을 두지 않으며, 같은 낱말이나 이름·부제에 있는 낱말을 다시 넣지 않는다.
- URL: https로 시작하고, 앱 안의 링크(`DayGrid/App/AppLinks.swift`)와 같아야 한다.
"""
import pathlib
import re
import sys

LIMITS = {
    "name.txt": 30,
    "subtitle.txt": 30,
    "promotional_text.txt": 170,
    "keywords.txt": 100,
    "description.txt": 4000,
    "release_notes.txt": 4000,
}
URL_FILES = {"support_url.txt": "support", "privacy_url.txt": "privacyPolicy", "marketing_url.txt": "website"}


def read(path):
    return path.read_text(encoding="utf-8").strip()


def main(root):
    root = pathlib.Path(root)
    metadata = root / "appstore" / "metadata"
    errors = []
    app_links = dict(re.findall(r'static let (\w+) = URL\(string: "([^"]+)"\)', read(root / "DayGrid" / "App" / "AppLinks.swift")))

    for locale_dir in sorted(p for p in metadata.iterdir() if p.is_dir() and p.name != "review_information"):
        print(f"[{locale_dir.name}]")
        for name, limit in LIMITS.items():
            path = locale_dir / name
            if not path.exists():
                continue
            text = read(path)
            print(f"  {name}: {len(text)}/{limit}")
            if len(text) > limit:
                errors.append(f"{path}: {len(text)}자(한도 {limit}자)")
            if not text:
                errors.append(f"{path}: 비어 있다")

        keywords_path = locale_dir / "keywords.txt"
        if keywords_path.exists():
            raw = read(keywords_path)
            words = raw.split(",")
            if any(w != w.strip() or not w for w in words):
                errors.append(f"{keywords_path}: 쉼표 앞뒤에 빈칸이나 빈 낱말이 있다")
            lowered = [w.strip().lower() for w in words]
            duplicates = sorted({w for w in lowered if lowered.count(w) > 1})
            if duplicates:
                errors.append(f"{keywords_path}: 겹치는 키워드 {duplicates}")
            title_words = set()
            for other in ("name.txt", "subtitle.txt"):
                if (locale_dir / other).exists():
                    title_words |= set(re.split(r"[\s·,:\-]+", read(locale_dir / other).lower()))
            repeated = sorted(set(lowered) & title_words)
            if repeated:
                errors.append(f"{keywords_path}: 이름·부제에 이미 있는 낱말 {repeated}(검색에 더 도움이 되지 않는다)")

        for name, key in URL_FILES.items():
            path = locale_dir / name
            if not path.exists():
                continue
            url = read(path)
            if not url.startswith("https://"):
                errors.append(f"{path}: https로 시작해야 한다")
            if key in app_links and app_links[key] != url:
                errors.append(f"{path}: 앱 안의 링크(AppLinks.{key} = {app_links[key]})와 다르다")

    notes = metadata / "review_information" / "notes.txt"
    if notes.exists() and len(read(notes)) > 4000:
        errors.append(f"{notes}: 4000자를 넘는다")

    for error in errors:
        print(f"::error::{error}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
