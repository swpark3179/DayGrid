"""TestFlight 내보내기용 서명 자산을 App Store Connect API로 만들고 지운다.

Xcode 자동 서명(클라우드 서명)은 iCloud 컨테이너를 찾을 때 API 키로 인증하지 못한다
(`appstoreconnect.apple.com/xcbuild/v1/cloudContainers` → 401 "Authentication failed", TestFlight 실행 #3·#4).
그래서 공개 API로 실행마다 배포 인증서와 App Store 프로파일을 만들고, 수동 서명으로 내보낸 뒤 지운다.
프로파일의 entitlements(iCloud 컨테이너, App Group, 푸시)는 developer.apple.com의 App ID 설정을 그대로 따른다.

사용법(TestFlight 워크플로):
    python3 scripts/ci/asc_signing.py prepare --archive build/DayGrid.xcarchive --out build/signing \
        --destination upload --export-options build/ExportOptions.plist
    python3 scripts/ci/asc_signing.py cleanup --out build/signing

환경 변수
- ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH: App Store Connect API 키(Admin)
- APPLE_TEAM_ID: 팀 ID
- P12_PASSWORD: prepare가 만드는 build/signing/distribution.p12의 암호(워크플로가 실행마다 만든다)
- GITHUB_RUN_ID: 프로파일 이름에 붙인다

표준 라이브러리와 macOS의 openssl, codesign, security만 쓴다.
"""
import argparse
import base64
import hashlib
import json
import os
import plistlib
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api.appstoreconnect.apple.com/v1"
PROFILE_PREFIX = "DayGrid CI "
# macOS 기본 openssl(LibreSSL)이 만든 .p12는 `security import`가 그대로 읽는다.
OPENSSL = "/usr/bin/openssl"
PROFILE_DIRS = [
    Path.home() / "Library/MobileDevice/Provisioning Profiles",
    Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
]

# entitlement 키 → App ID에서 켜야 하는 기능(공개 API의 capabilityType)과 사용자 안내
CAPABILITIES = {
    "com.apple.developer.icloud-container-identifiers": ("ICLOUD", "iCloud(CloudKit)", "docs/ICLOUD.md 2번"),
    "aps-environment": ("PUSH_NOTIFICATIONS", "Push Notifications", "docs/ICLOUD.md 2번"),
    "com.apple.security.application-groups": ("APP_GROUPS", "App Groups", "docs/WIDGET.md 2–3번"),
}


def fail(message):
    print(f"::error::{message}")
    sys.exit(1)


# MARK: - 인증 토큰(ES256 JWT)

def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_signature_to_raw(der, size=32):
    """openssl이 내는 ECDSA 서명(DER: SEQUENCE { INTEGER r, INTEGER s })을 JWT 형식(r || s, 각 32바이트)으로 바꾼다."""
    if len(der) < 8 or der[0] != 0x30:
        raise ValueError("ECDSA 서명이 DER SEQUENCE가 아니다")
    index = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    raw = b""
    for _ in range(2):
        if der[index] != 0x02:
            raise ValueError("ECDSA 서명에 INTEGER가 없다")
        length = der[index + 1]
        value = der[index + 2:index + 2 + length].lstrip(b"\x00")
        if len(value) > size:
            raise ValueError("ECDSA 서명 값이 너무 길다")
        raw += value.rjust(size, b"\x00")
        index += 2 + length
    return raw


def make_token(key_id, issuer_id, key_path, now=None):
    now = int(time.time() if now is None else now)
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"}
    signing_input = ".".join(
        b64url(json.dumps(part, separators=(",", ":")).encode()) for part in (header, payload)
    )
    der = subprocess.run(
        [OPENSSL, "dgst", "-sha256", "-sign", key_path],
        input=signing_input.encode(), capture_output=True, check=True,
    ).stdout
    return f"{signing_input}.{b64url(der_signature_to_raw(der))}"


# MARK: - API

class Client:
    def __init__(self, token):
        self.token = token

    def request(self, method, path, body=None, params=None, allow_missing=False):
        url = API + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=data, method=method, headers={
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
        })
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            if allow_missing and error.code == 404:
                return None
            raise ApiError(method, path, error.code, error.read().decode(errors="replace")) from None


class ApiError(Exception):
    def __init__(self, method, path, status, body):
        self.status = status
        try:
            errors = json.loads(body).get("errors", [])
            detail = "; ".join(f"{e.get('title', '')}: {e.get('detail', '')}" for e in errors) or body
        except ValueError:
            detail = body
        super().__init__(f"App Store Connect API {method} {path} → {status}: {detail[:600]}")


# MARK: - 아카이브

def archive_bundles(archive):
    """아카이브 안의 앱과 확장(.appex). 확장을 먼저 둔다."""
    apps = sorted((Path(archive) / "Products/Applications").glob("*.app"))
    if not apps:
        fail(f"{archive}에 앱이 없다")
    bundles = []
    for app in apps:
        bundles += sorted(app.glob("PlugIns/*.appex"))
        bundles.append(app)
    return bundles


def bundle_identifier(bundle):
    with open(bundle / "Info.plist", "rb") as file:
        return plistlib.load(file)["CFBundleIdentifier"]


def signed_entitlements(bundle):
    output = subprocess.run(
        ["codesign", "-d", "--entitlements", "-", "--xml", str(bundle)],
        capture_output=True, check=True,
    ).stdout
    start = output.find(b"<?xml")
    return plistlib.loads(output[start:]) if start >= 0 else {}


def missing_profile_entitlements(required, granted):
    """프로파일이 허락하지 않는 entitlement(사람이 읽을 문구). 값이 목록이면 하나하나 확인한다."""
    missing = []
    for key in CAPABILITIES:
        if key not in required:
            continue
        if key not in granted:
            missing.append(key)
            continue
        wanted = required[key] if isinstance(required[key], list) else [required[key]]
        allowed = granted[key] if isinstance(granted[key], list) else [granted[key]]
        if "*" in allowed or key == "aps-environment":
            continue
        for value in wanted:
            if value not in allowed:
                missing.append(f"{key} = {value}")
    return missing


# MARK: - prepare / cleanup

def load_state(out):
    path = Path(out) / "state.json"
    return json.loads(path.read_text()) if path.exists() else {"certificate": None, "profiles": []}


def save_state(out, state):
    (Path(out) / "state.json").write_text(json.dumps(state, indent=2))


def remove_stale(client):
    """이전 실행이 정리하지 못한 "DayGrid CI" 프로파일과 그 인증서를 지운다(이 스크립트가 만든 것만)."""
    response = client.request("GET", "/profiles", params={"filter[profileType]": "IOS_APP_STORE", "limit": 200})
    for profile in response.get("data", []):
        name = profile["attributes"].get("name", "")
        if not name.startswith(PROFILE_PREFIX):
            continue
        certificates = client.request("GET", f"/profiles/{profile['id']}/certificates") or {"data": []}
        client.request("DELETE", f"/profiles/{profile['id']}", allow_missing=True)
        print(f"이전 프로파일 삭제: {name}")
        for certificate in certificates.get("data", []):
            client.request("DELETE", f"/certificates/{certificate['id']}", allow_missing=True)
            print(f"이전 인증서 폐기: {certificate['id']}")


def find_bundle_id(client, identifier):
    response = client.request("GET", "/bundleIds", params={"filter[identifier]": identifier, "limit": 200})
    for item in response.get("data", []):
        if item["attributes"]["identifier"] == identifier:
            return item["id"]
    fail(f"App ID {identifier}가 developer.apple.com에 없다. docs/TESTFLIGHT.md 1번(위젯이면 docs/WIDGET.md 3번)을 확인한다.")


def check_capabilities(client, bundle_resource_id, identifier, entitlements):
    response = client.request("GET", f"/bundleIds/{bundle_resource_id}/bundleIdCapabilities")
    enabled = {item["attributes"]["capabilityType"] for item in response.get("data", [])}
    for key, (capability, label, doc) in CAPABILITIES.items():
        if key in entitlements and capability not in enabled:
            fail(f"App ID {identifier}에 {label}가 꺼져 있다. {doc}대로 켠다.")


def make_certificate(client, out, state):
    key = Path(out) / "distribution.key"
    csr = Path(out) / "distribution.csr"
    subprocess.run([OPENSSL, "genrsa", "-out", str(key), "2048"], check=True, capture_output=True)
    subprocess.run([OPENSSL, "req", "-new", "-key", str(key), "-subj", "/CN=DayGrid CI", "-out", str(csr)],
                   check=True, capture_output=True)
    body = {"data": {"type": "certificates", "attributes": {
        "certificateType": "DISTRIBUTION",
        "csrContent": csr.read_text(),
    }}}
    try:
        response = client.request("POST", "/certificates", body=body)
    except ApiError as error:
        if error.status == 409:
            fail(f"배포 인증서를 더 만들 수 없다(한도). developer.apple.com → Certificates에서 쓰지 않는 "
                 f"Apple Distribution 인증서를 폐기(Revoke)한 뒤 다시 실행한다. ({error})")
        raise
    certificate = response["data"]
    state["certificate"] = certificate["id"]
    save_state(out, state)

    der = base64.b64decode(certificate["attributes"]["certificateContent"])
    (Path(out) / "distribution.cer").write_bytes(der)
    pem = Path(out) / "distribution.pem"
    subprocess.run([OPENSSL, "x509", "-inform", "DER", "-in", str(Path(out) / "distribution.cer"), "-out", str(pem)],
                   check=True, capture_output=True)
    subprocess.run([OPENSSL, "pkcs12", "-export", "-inkey", str(key), "-in", str(pem),
                    "-out", str(Path(out) / "distribution.p12"), "-passout", "env:P12_PASSWORD"],
                   check=True, capture_output=True)
    print(f"배포 인증서 생성: {certificate['attributes'].get('name', '')} ({certificate['id']})")
    return certificate["id"], hashlib.sha1(der).hexdigest().upper()


def make_profile(client, out, state, identifier, bundle_resource_id, certificate_id):
    name = f"{PROFILE_PREFIX}{os.environ.get('GITHUB_RUN_ID', int(time.time()))} {identifier}"
    body = {"data": {
        "type": "profiles",
        "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}},
            "certificates": {"data": [{"type": "certificates", "id": certificate_id}]},
        },
    }}
    profile = client.request("POST", "/profiles", body=body)["data"]
    state["profiles"].append(profile["id"])
    save_state(out, state)

    uuid = profile["attributes"]["uuid"]
    content = base64.b64decode(profile["attributes"]["profileContent"])
    for directory in PROFILE_DIRS:
        directory.mkdir(parents=True, exist_ok=True)
        (directory / f"{uuid}.mobileprovision").write_bytes(content)
    path = Path(out) / f"{identifier}.mobileprovision"
    path.write_bytes(content)
    print(f"프로파일 생성: {name} ({uuid})")
    return uuid, path


def profile_entitlements(path):
    decoded = subprocess.run(["security", "cms", "-D", "-i", str(path)], capture_output=True, check=True).stdout
    return plistlib.loads(decoded).get("Entitlements", {})


def write_export_options(path, destination, team_id, certificate_sha1, profiles):
    options = {
        "method": "app-store-connect",
        "destination": destination,
        "teamID": team_id,
        "signingStyle": "manual",
        "signingCertificate": certificate_sha1,
        "provisioningProfiles": profiles,
        "uploadSymbols": True,
        "manageAppVersionAndBuildNumber": False,
    }
    with open(path, "wb") as file:
        plistlib.dump(options, file)


def client_from_environment():
    for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH"):
        if not os.environ.get(name):
            fail(f"환경 변수 {name}가 없다")
    return Client(make_token(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], os.environ["ASC_KEY_PATH"]))


def prepare(args):
    if not os.environ.get("P12_PASSWORD") or not os.environ.get("APPLE_TEAM_ID"):
        fail("환경 변수 P12_PASSWORD, APPLE_TEAM_ID가 필요하다")
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    state = load_state(out)
    client = client_from_environment()

    bundles = [(bundle, bundle_identifier(bundle), signed_entitlements(bundle)) for bundle in archive_bundles(args.archive)]
    resources = {}
    for _, identifier, entitlements in bundles:
        resources[identifier] = find_bundle_id(client, identifier)
        check_capabilities(client, resources[identifier], identifier, entitlements)

    remove_stale(client)
    certificate_id, certificate_sha1 = make_certificate(client, out, state)

    profiles = {}
    for _, identifier, entitlements in bundles:
        uuid, path = make_profile(client, out, state, identifier, resources[identifier], certificate_id)
        missing = missing_profile_entitlements(entitlements, profile_entitlements(path))
        if missing:
            fail(f"{identifier} 프로파일에 없는 entitlement: {', '.join(missing)}. "
                 "developer.apple.com의 App ID에서 iCloud 컨테이너나 App Group을 체크했는지 확인한다"
                 "(docs/ICLOUD.md 2번, docs/WIDGET.md 2–3번).")
        profiles[identifier] = uuid

    write_export_options(args.export_options, args.destination, os.environ["APPLE_TEAM_ID"], certificate_sha1, profiles)
    print(f"ExportOptions: {args.export_options} (수동 서명, {len(profiles)}개 프로파일)")


def cleanup(args):
    state = load_state(args.out)
    if not state["profiles"] and not state["certificate"]:
        print("지울 서명 자산이 없다")
        return
    client = client_from_environment()
    errors = []
    for profile_id in state["profiles"]:
        try:
            client.request("DELETE", f"/profiles/{profile_id}", allow_missing=True)
            print(f"프로파일 삭제: {profile_id}")
        except ApiError as error:
            errors.append(str(error))
    if state["certificate"]:
        try:
            client.request("DELETE", f"/certificates/{state['certificate']}", allow_missing=True)
            print(f"인증서 폐기: {state['certificate']}")
        except ApiError as error:
            errors.append(str(error))
    save_state(args.out, {"certificate": None, "profiles": []})
    for error in errors:
        # 다음 실행의 prepare가 "DayGrid CI" 프로파일과 그 인증서를 다시 지운다.
        print(f"::warning::{error}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    prepare_parser = commands.add_parser("prepare")
    prepare_parser.add_argument("--archive", required=True)
    prepare_parser.add_argument("--out", required=True)
    prepare_parser.add_argument("--destination", choices=["upload", "export"], default="upload")
    prepare_parser.add_argument("--export-options", required=True)
    cleanup_parser = commands.add_parser("cleanup")
    cleanup_parser.add_argument("--out", required=True)
    args = parser.parse_args()
    try:
        prepare(args) if args.command == "prepare" else cleanup(args)
    except ApiError as error:
        fail(str(error))


if __name__ == "__main__":
    main()
