"""App Store 스크린샷용 6.9형 iPhone 시뮬레이터의 UDID를 출력한다. 없으면 만든다.

사용법: udid=$(python3 scripts/appstore/large_simulator.py)

가장 최신 iOS 런타임에서 아래 기기를 순서대로 찾는다. 6.9형(1320x2868, 1290x2796, 1260x2736)만 쓴다.
"""
import json
import re
import subprocess
import sys

PREFERRED = ["iPhone 17 Pro Max", "iPhone 16 Pro Max", "iPhone Air", "iPhone 16 Plus", "iPhone 15 Pro Max"]


def version_of(runtime):
    match = re.search(r"iOS-(\d+)-(\d+)(?:-(\d+))?$", runtime.get("identifier", ""))
    return tuple(int(part or 0) for part in match.groups()) if match else None


def main():
    data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "--json"], text=True))
    runtimes = [r for r in data.get("runtimes", []) if r.get("isAvailable", True) and version_of(r)]
    if not runtimes:
        sys.exit("iOS 시뮬레이터 런타임이 없습니다")
    runtime = max(runtimes, key=version_of)
    devices = [d for d in data.get("devices", {}).get(runtime["identifier"], []) if d.get("isAvailable", True)]
    device_types = {t["name"]: t["identifier"] for t in data.get("devicetypes", [])}
    supported = {t.get("name") for t in runtime.get("supportedDeviceTypes", [])} or set(device_types)

    for name in PREFERRED:
        found = next((d for d in devices if d.get("name") == name), None)
        if found:
            print(f"Using {name} ({runtime['name']}) {found['udid']}", file=sys.stderr)
            print(found["udid"])
            return
    for name in PREFERRED:
        if name in device_types and name in supported:
            udid = subprocess.check_output(
                ["xcrun", "simctl", "create", f"AppStore {name}", device_types[name], runtime["identifier"]], text=True
            ).strip()
            print(f"Created {name} ({runtime['name']}) {udid}", file=sys.stderr)
            print(udid)
            return
    sys.exit(f"6.9형 iPhone 시뮬레이터가 없습니다. 찾은 기기: {[d.get('name') for d in devices]}")


if __name__ == "__main__":
    main()
