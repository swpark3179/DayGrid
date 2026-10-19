"""`xcresulttool export attachments`로 꺼낸 파일을 사람이 읽을 수 있는 이름으로 바꾼다.

사용법: python3 scripts/ci/export_screenshots.py <내보낸 폴더>
폴더 안의 manifest.json에 있는 suggestedHumanReadableName을 쓴다.
"""
import json
import pathlib
import sys


def main(folder):
    folder = pathlib.Path(folder)
    manifest_path = folder / "manifest.json"
    if not manifest_path.exists():
        print(f"{manifest_path} not found; leaving files as exported")
        return
    for test in json.loads(manifest_path.read_text()):
        for attachment in test.get("attachments", []):
            exported = folder / attachment.get("exportedFileName", "")
            readable = attachment.get("suggestedHumanReadableName")
            if exported.is_file() and readable:
                target = folder / readable
                exported.rename(target)
                print(f"{exported.name} -> {target.name}")


if __name__ == "__main__":
    main(sys.argv[1])
