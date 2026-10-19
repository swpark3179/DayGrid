"""`xcresulttool export attachments`로 꺼낸 폴더를 정리한다.

사용법: python3 scripts/ci/export_screenshots.py <내보낸 폴더>

- UI 테스트가 `NN-이름`으로 남긴 PNG 스크린샷만 `NN-이름.png`로 남긴다.
- 실패할 때 XCTest가 붙이는 텍스트 첨부(UI 계층, 요소 설명)는 내용을 로그에 출력한 뒤 지운다.
  이 파일들은 이름에 따옴표가 들어 있어 upload-artifact가 거부하고, 내용은 로그에서 보는 편이 낫다.
- 나머지(UI 스냅샷, 이벤트, 화면 녹화)와 manifest.json도 지운다.
"""
import json
import pathlib
import re
import sys

SCREENSHOT_NAME = re.compile(r"^(\d\d-[A-Za-z0-9-]+?)(?:_\d+_[0-9A-Fa-f-]{36})?\.png$")
TEXT_ATTACHMENT_PREFIXES = ("App UI hierarchy", "Debug description")


def main(folder):
    folder = pathlib.Path(folder)
    manifest_path = folder / "manifest.json"
    if not manifest_path.exists():
        print(f"{manifest_path} not found; leaving files as exported")
        return

    kept = []
    for test in json.loads(manifest_path.read_text()):
        test_id = test.get("testIdentifier", "?")
        for attachment in test.get("attachments", []):
            exported = folder / attachment.get("exportedFileName", "")
            readable = attachment.get("suggestedHumanReadableName", "")
            if not exported.is_file():
                continue
            match = SCREENSHOT_NAME.match(readable)
            if match:
                target = folder / f"{match.group(1)}.png"
                exported.rename(target)
                kept.append(target.name)
                continue
            if readable.startswith(TEXT_ATTACHMENT_PREFIXES):
                print(f"::group::{test_id} — {readable}")
                print(exported.read_text(errors="replace"))
                print("::endgroup::")
            exported.unlink()

    manifest_path.unlink()
    print("screenshots:", ", ".join(sorted(kept)) or "(none)")


if __name__ == "__main__":
    main(sys.argv[1])
