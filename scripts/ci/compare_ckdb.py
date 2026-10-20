"""커밋한 CloudKit 스키마(`cloudkit/DayGrid.ckdb`)와 서버에서 내려받은 스키마를 비교해 마크다운으로 보여준다.

    python3 scripts/ci/compare_ckdb.py cloudkit/DayGrid.ckdb build/production.ckdb Production

- 레코드 타입과 필드 이름·타입만 본다. 시스템 필드(`___`로 시작), 색인 표시(QUERYABLE 등), 권한(GRANT)은 보지 않는다.
- 서버에만 있는 것은 문제가 아니다(Production 필드는 지울 수 없다). 커밋한 파일에만 있거나 타입이 다른 것만 알린다.
- 다른 점이 있으면 종료 코드 1을 돌려준다.
"""
import re
import sys

RECORD_TYPE = re.compile(r"^\s*RECORD TYPE\s+(\w+)\s*\(")
FIELD = re.compile(r'^\s*("?)(\w+)\1\s+([A-Z0-9_]+(?:<[A-Z0-9_]+>)?)')


def parse(path):
    """{레코드 타입: {필드: 타입}}"""
    types = {}
    current = None
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.split("//", 1)[0].rstrip()
            match = RECORD_TYPE.match(line)
            if match:
                current = types.setdefault(match.group(1), {})
                continue
            if current is None:
                continue
            if line.strip().startswith(");"):
                current = None
                continue
            match = FIELD.match(line)
            if not match or match.group(2) == "GRANT" or match.group(2).startswith("___"):
                continue
            current[match.group(2)] = match.group(3)
    return types


def compare(expected, actual):
    """(없는 레코드 타입, 없는 필드, 타입이 다른 필드)"""
    missing_types = sorted(name for name in expected if name not in actual)
    missing_fields = []
    wrong_types = []
    for name in sorted(expected):
        if name not in actual:
            continue
        for field, kind in sorted(expected[name].items()):
            if field not in actual[name]:
                missing_fields.append(f"{name}.{field} {kind}")
            elif actual[name][field] != kind:
                wrong_types.append(f"{name}.{field}: 파일 {kind}, 서버 {actual[name][field]}")
    return missing_types, missing_fields, wrong_types


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: compare_ckdb.py <expected.ckdb> <actual.ckdb> <environment name>")
    expected_path, actual_path, environment = sys.argv[1:]
    expected = parse(expected_path)
    actual = parse(actual_path)
    missing_types, missing_fields, wrong_types = compare(expected, actual)

    print(f"### {environment} 스키마 비교")
    if not (missing_types or missing_fields or wrong_types):
        print(f"{environment}에 `{expected_path}`의 레코드 타입 {len(expected)}개와 필드가 모두 있다.")
        return
    if missing_types:
        print(f"- {environment}에 없는 레코드 타입({len(missing_types)}개): " + ", ".join(f"`{t}`" for t in missing_types))
    if missing_fields:
        print(f"- {environment}에 없는 필드({len(missing_fields)}개):")
        for field in missing_fields:
            print(f"  - `{field}`")
    if wrong_types:
        print(f"- 타입이 다른 필드({len(wrong_types)}개):")
        for field in wrong_types:
            print(f"  - `{field}`")
    sys.exit(1)


if __name__ == "__main__":
    main()
