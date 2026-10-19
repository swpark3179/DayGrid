"""`xcrun simctl list devices available --json` 출력(stdin)에서 테스트할 iPhone 시뮬레이터 UDID를 고른다.

가장 최신 iOS 런타임 중에서 선호 기기 이름 순서대로 찾고, 없으면 그 런타임의 첫 iPhone을 쓴다.
"""
import json
import re
import sys

PREFERRED_NAMES = ["iPhone 17", "iPhone 17 Pro", "iPhone 16", "iPhone 16 Pro"]


def runtime_version(runtime_id):
    match = re.search(r"iOS-(\d+)-(\d+)(?:-(\d+))?$", runtime_id)
    if not match:
        return None
    return tuple(int(part or 0) for part in match.groups())


def main():
    devices_by_runtime = json.load(sys.stdin).get("devices", {})
    runtimes = []
    for runtime_id, devices in devices_by_runtime.items():
        version = runtime_version(runtime_id)
        iphones = [d for d in devices if d.get("isAvailable", True) and d.get("name", "").startswith("iPhone")]
        if version and iphones:
            runtimes.append((version, iphones))
    if not runtimes:
        sys.exit("No available iPhone simulator found")

    version, iphones = max(runtimes, key=lambda item: item[0])
    by_name = {d["name"]: d for d in iphones}
    chosen = next((by_name[name] for name in PREFERRED_NAMES if name in by_name), iphones[0])
    print(f"Using {chosen['name']} (iOS {'.'.join(map(str, version))}) {chosen['udid']}", file=sys.stderr)
    print(chosen["udid"])


if __name__ == "__main__":
    main()
