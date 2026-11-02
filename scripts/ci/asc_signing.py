"""TestFlight 내보내기용 서명 자산(배포 인증서, App Store 프로파일)을 App Store Connect API로 준비한다.

Xcode 자동 서명(클라우드 서명)은 iCloud 컨테이너를 찾을 때 API 키로 인증하지 못한다
(`appstoreconnect.apple.com/xcbuild/v1/cloudContainers` → 401 "Authentication failed", TestFlight 실행 #3·#4).
그래서 공개 API로 인증서와 프로파일을 준비하고, 수동 서명으로 내보낸다.
프로파일의 entitlements(iCloud 컨테이너, App Group, 푸시)는 developer.apple.com의 App ID 설정을 그대로 따른다.

- 배포 인증서는 한 번 만들어 GitHub Secrets에 두고 계속 쓴다. 이 스크립트는 인증서를 폐기하지 않는다.
  폐기한 인증서로 서명한 빌드는 App Store 심사에서 "잘못된 바이너리"가 된다(TestFlight는 그대로 돈다).
- 프로파일은 번들마다 "DayGrid CI <번들 ID>" 하나를 두고 다시 쓴다.

사용법(TestFlight 워크플로):
    python3 scripts/ci/asc_signing.py prepare --archive build/DayGrid.xcarchive --out build/signing \
        --destination upload --export-options build/ExportOptions.plist
  → build/signing/distribution.p12와 그 암호(build/signing/p12-password)를 남긴다. 워크플로가 키체인에 넣고 지운다.

환경 변수
- ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH: App Store Connect API 키(Admin)
- APPLE_TEAM_ID: 팀 ID
- DIST_P12_BASE64, DIST_P12_PASSWORD: Secrets에 둔 배포 인증서(.p12의 base64)와 그 암호. 처음에는 없다.
- SECRETS_TOKEN: 위 두 Secret을 처음 만들 때(또는 인증서가 만료됐을 때)만 쓰는 토큰(저장소 Secrets 쓰기 권한)
- GITHUB_REPOSITORY: Secret을 넣을 저장소(Actions가 넣어 준다)

표준 라이브러리와 macOS의 openssl, codesign, security, gh만 쓴다.
"""
import argparse
import base64
import hashlib
import json
import os
import plistlib
import secrets
import shutil
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


def fail_all(problems):
    """문제를 모두 보여 주고 끝낸다. 한 번 실행으로 developer.apple.com에서 고칠 것을 다 알 수 있게."""
    for problem in problems:
        print(f"::error::{problem}")
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


# MARK: - App ID

def find_bundle_id(client, identifier):
    """App ID의 리소스 id. 없으면 `None`."""
    response = client.request("GET", "/bundleIds", params={"filter[identifier]": identifier, "limit": 200})
    for item in response.get("data", []):
        if item["attributes"]["identifier"] == identifier:
            return item["id"]
    return None


def capability_problems(client, bundle_resource_id, identifier, entitlements):
    """아카이브의 entitlements에 필요한데 App ID에서 꺼져 있는 기능(사람이 읽을 문구)."""
    response = client.request("GET", f"/bundleIds/{bundle_resource_id}/bundleIdCapabilities")
    enabled = {item["attributes"]["capabilityType"] for item in response.get("data", [])}
    return [
        f"App ID {identifier}에 {label}가 꺼져 있다. {doc}대로 켠다."
        for key, (capability, label, doc) in CAPABILITIES.items()
        if key in entitlements and capability not in enabled
    ]


# MARK: - 배포 인증서
# 배포 인증서는 한 번 만들어 GitHub Secrets(DIST_P12_BASE64, DIST_P12_PASSWORD)에 두고 계속 쓴다. 폐기하지 않는다.
# 폐기한 인증서로 서명한 빌드는 TestFlight에서는 그대로 돌지만, App Store 심사에서는 "잘못된 바이너리(Invalid Binary)"가 된다
# (https://developer.apple.com/support/certificates/ "Expired or revoked certificates"). 2026-11 첫 심사에서 이 일이 있었다.

def p12_certificate(p12, password):
    """.p12 안의 인증서(DER). 암호가 틀리거나 파일이 깨졌으면 `None`."""
    env = dict(os.environ, DAYGRID_P12_IN=password)
    result = subprocess.run([OPENSSL, "pkcs12", "-in", str(p12), "-clcerts", "-nokeys", "-passin", "env:DAYGRID_P12_IN"],
                            capture_output=True, env=env)
    if result.returncode != 0:
        return None
    der = subprocess.run([OPENSSL, "x509", "-outform", "DER"], input=result.stdout, capture_output=True)
    return der.stdout if der.returncode == 0 and der.stdout else None


def find_certificate(client, der, today=None):
    """App Store Connect에 살아 있는 배포 인증서 중 `der`와 같은 것의 id. 폐기됐거나 만료됐으면 `None`."""
    today = today or time.strftime("%Y-%m-%d", time.gmtime())
    digest = hashlib.sha1(der).digest()
    response = client.request("GET", "/certificates", params={"filter[certificateType]": "DISTRIBUTION", "limit": 200})
    for item in response.get("data", []):
        attributes = item.get("attributes", {})
        content = attributes.get("certificateContent")
        if not content or hashlib.sha1(base64.b64decode(content)).digest() != digest:
            continue
        expiration = attributes.get("expirationDate") or ""
        if expiration and expiration[:10] <= today:
            print(f"::warning::저장한 배포 인증서가 만료됐다({expiration[:10]}).")
            return None
        return item["id"]
    return None


def create_certificate(client, out, password):
    """새 배포 인증서를 만들고 `out/distribution.p12`(암호 `password`)로 묶는다. (인증서 id, DER)"""
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
                 f"Apple Distribution 인증서를 폐기(Revoke)한 뒤 다시 실행한다. 폐기한 인증서로 서명한 빌드는 "
                 f"심사에서 잘못된 바이너리가 되므로, 심사를 기다리는 빌드가 없을 때만 폐기한다. ({error})")
        raise
    certificate = response["data"]
    der = base64.b64decode(certificate["attributes"]["certificateContent"])
    cer = Path(out) / "distribution.cer"
    pem = Path(out) / "distribution.pem"
    cer.write_bytes(der)
    subprocess.run([OPENSSL, "x509", "-inform", "DER", "-in", str(cer), "-out", str(pem)], check=True, capture_output=True)
    env = dict(os.environ, DAYGRID_P12_OUT=password)
    subprocess.run([OPENSSL, "pkcs12", "-export", "-inkey", str(key), "-in", str(pem),
                    "-out", str(Path(out) / "distribution.p12"), "-passout", "env:DAYGRID_P12_OUT"],
                   check=True, capture_output=True, env=env)
    key.unlink()
    print(f"배포 인증서 생성: {certificate['attributes'].get('name', '')} ({certificate['id']})")
    return certificate["id"], der


def store_certificate_secrets(p12, password):
    """만든 인증서를 저장소 Secrets에 넣는다. SECRETS_TOKEN(Secrets 쓰기 권한의 토큰)과 gh CLI를 쓴다."""
    repository = os.environ.get("GITHUB_REPOSITORY")
    if not repository or not shutil.which("gh"):
        raise RuntimeError("GITHUB_REPOSITORY 환경 변수나 gh CLI가 없다")
    env = dict(os.environ, GH_TOKEN=os.environ["SECRETS_TOKEN"])
    values = {
        "DIST_P12_BASE64": base64.b64encode(Path(p12).read_bytes()).decode(),
        "DIST_P12_PASSWORD": password,
    }
    for name, value in values.items():
        # 값은 명령 인자 대신 표준 입력으로 넘긴다(프로세스 목록과 로그에 남지 않게).
        result = subprocess.run(["gh", "secret", "set", name, "--repo", repository],
                                input=value.encode(), capture_output=True, env=env)
        if result.returncode != 0:
            raise RuntimeError(f"gh secret set {name}: {result.stderr.decode(errors='replace').strip()[:300]}")
        print(f"Secret 저장: {name}")


def ensure_certificate(client, out):
    """쓸 배포 인증서를 정한다. `out/distribution.p12`와 `out/p12-password`를 남기고 (인증서 id, SHA-1)을 돌려준다.

    1. Secrets의 인증서가 App Store Connect에 살아 있으면 그대로 쓴다.
    2. 없으면(처음이거나 만료) SECRETS_TOKEN이 있을 때만 새로 만들어 Secrets에 넣는다.
    """
    p12 = Path(out) / "distribution.p12"
    saved = os.environ.get("DIST_P12_BASE64", "").strip()
    saved_password = os.environ.get("DIST_P12_PASSWORD", "")
    if saved:
        try:
            p12.write_bytes(base64.b64decode(saved))
        except ValueError:
            fail("Secret DIST_P12_BASE64가 base64가 아니다. 지우고 SECRETS_TOKEN으로 다시 만든다(docs/TESTFLIGHT.md 5-1).")
        der = p12_certificate(p12, saved_password)
        if der is None:
            fail("Secret DIST_P12_BASE64를 DIST_P12_PASSWORD로 열 수 없다. 두 Secret을 지우고 SECRETS_TOKEN으로 다시 만든다"
                 "(docs/TESTFLIGHT.md 5-1).")
        certificate_id = find_certificate(client, der)
        if certificate_id:
            (Path(out) / "p12-password").write_text(saved_password)
            print(f"저장한 배포 인증서를 쓴다({certificate_id})")
            return certificate_id, hashlib.sha1(der).hexdigest().upper()
        print("::warning::Secrets의 배포 인증서가 App Store Connect에 없다(폐기 또는 만료). 새로 만든다.")

    if not os.environ.get("SECRETS_TOKEN"):
        fail("쓸 수 있는 배포 인증서가 없다. docs/TESTFLIGHT.md 5-1대로 Secret SECRETS_TOKEN을 넣고 다시 실행하면 "
             "인증서를 한 번 만들어 DIST_P12_BASE64, DIST_P12_PASSWORD에 저장한다.")
    password = secrets.token_urlsafe(32)
    print(f"::add-mask::{password}")
    certificate_id, der = create_certificate(client, out, password)
    try:
        store_certificate_secrets(p12, password)
    except RuntimeError as error:
        # 아직 이 인증서로 서명한 빌드가 없으니 폐기해도 된다. 남겨 두면 한도만 찬다.
        client.request("DELETE", f"/certificates/{certificate_id}", allow_missing=True)
        fail(f"새 배포 인증서를 Secrets에 저장하지 못해 폐기했다. SECRETS_TOKEN의 권한(Secrets: Read and write)을 확인한다. ({error})")
    (Path(out) / "p12-password").write_text(password)
    return certificate_id, hashlib.sha1(der).hexdigest().upper()


# MARK: - 프로파일
# 번들마다 이름이 정해진 프로파일("DayGrid CI <번들 ID>") 하나를 두고, 쓸 수 있으면 다시 쓴다.
# 실행마다 지우지 않는다. 인증서가 바뀌었거나 entitlements가 모자랄 때만 지우고 새로 만든다.

def profile_name(identifier):
    return f"{PROFILE_PREFIX}{identifier}"


def ci_profiles(client):
    """이 스크립트가 만든 App Store 프로파일("DayGrid CI …")."""
    response = client.request("GET", "/profiles", params={"filter[profileType]": "IOS_APP_STORE", "limit": 200})
    return [p for p in response.get("data", []) if p["attributes"].get("name", "").startswith(PROFILE_PREFIX)]


def remove_old_profiles(client, profiles, keep_names):
    """예전 방식(실행마다 이름이 다른 프로파일)으로 남은 것을 지운다. 인증서는 건드리지 않는다."""
    for profile in profiles:
        name = profile["attributes"]["name"]
        if name not in keep_names:
            client.request("DELETE", f"/profiles/{profile['id']}", allow_missing=True)
            print(f"예전 프로파일 삭제: {name}")


def profile_content(client, profile):
    content = profile["attributes"].get("profileContent")
    if not content:
        content = client.request("GET", f"/profiles/{profile['id']}")["data"]["attributes"]["profileContent"]
    return base64.b64decode(content)


def install_profile(out, identifier, uuid, content):
    for directory in PROFILE_DIRS:
        directory.mkdir(parents=True, exist_ok=True)
        (directory / f"{uuid}.mobileprovision").write_bytes(content)
    path = Path(out) / f"{identifier}.mobileprovision"
    path.write_bytes(content)
    return path


def reusable_profile(client, out, profile, identifier, certificate_id, entitlements):
    """다시 쓸 수 있으면 설치한 파일 경로, 아니면 `None`."""
    if profile["attributes"].get("profileState") != "ACTIVE":
        return None
    certificates = client.request("GET", f"/profiles/{profile['id']}/certificates") or {"data": []}
    if certificate_id not in {item["id"] for item in certificates.get("data", [])}:
        return None
    path = install_profile(out, identifier, profile["attributes"]["uuid"], profile_content(client, profile))
    return None if missing_profile_entitlements(entitlements, profile_entitlements(path)) else path


def ensure_profile(client, out, existing, identifier, bundle_resource_id, certificate_id, entitlements):
    """(uuid, 설치한 파일 경로)"""
    name = profile_name(identifier)
    same_name = [p for p in existing if p["attributes"]["name"] == name]
    for profile in same_name:
        path = reusable_profile(client, out, profile, identifier, certificate_id, entitlements)
        if path:
            print(f"프로파일 다시 씀: {name} ({profile['attributes']['uuid']})")
            return profile["attributes"]["uuid"], path
    for profile in same_name:
        client.request("DELETE", f"/profiles/{profile['id']}", allow_missing=True)
        print(f"프로파일 삭제(인증서나 entitlements가 맞지 않음): {name}")

    body = {"data": {
        "type": "profiles",
        "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}},
            "certificates": {"data": [{"type": "certificates", "id": certificate_id}]},
        },
    }}
    profile = client.request("POST", "/profiles", body=body)["data"]
    uuid = profile["attributes"]["uuid"]
    path = install_profile(out, identifier, uuid, base64.b64decode(profile["attributes"]["profileContent"]))
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


# MARK: - prepare

def prepare(args):
    if not os.environ.get("APPLE_TEAM_ID"):
        fail("환경 변수 APPLE_TEAM_ID가 필요하다")
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    client = client_from_environment()

    bundles = [(bundle, bundle_identifier(bundle), signed_entitlements(bundle)) for bundle in archive_bundles(args.archive)]
    # 인증서를 정하기 전에 모든 App ID를 확인하고, 문제는 한꺼번에 알린다.
    resources = {}
    problems = []
    for _, identifier, entitlements in bundles:
        resource_id = find_bundle_id(client, identifier)
        if resource_id is None:
            doc = "docs/WIDGET.md 3번" if identifier.endswith(".Widgets") else "docs/TESTFLIGHT.md 1번"
            problems.append(f"App ID {identifier}가 developer.apple.com에 없다. {doc}대로 만든다.")
            continue
        resources[identifier] = resource_id
        problems += capability_problems(client, resource_id, identifier, entitlements)
    if problems:
        fail_all(problems)

    certificate_id, certificate_sha1 = ensure_certificate(client, out)

    existing = ci_profiles(client)
    remove_old_profiles(client, existing, {profile_name(identifier) for _, identifier, _ in bundles})
    # 프로파일도 모두 확인한 뒤 한꺼번에 알린다.
    profiles = {}
    for _, identifier, entitlements in bundles:
        uuid, path = ensure_profile(client, out, existing, identifier, resources[identifier], certificate_id, entitlements)
        granted = profile_entitlements(path)
        missing = missing_profile_entitlements(entitlements, granted)
        if missing:
            shown = {key: granted.get(key, "(없음)") for key in CAPABILITIES if key in entitlements}
            problems.append(
                f"{identifier} 프로파일에 없는 entitlement: {', '.join(missing)}. 프로파일에 있는 값: {shown}. "
                "developer.apple.com의 App ID에서 iCloud 컨테이너나 App Group을 체크했는지 확인한다"
                "(docs/ICLOUD.md 2번, docs/WIDGET.md 2–3번)."
            )
        profiles[identifier] = uuid
    if problems:
        fail_all(problems)

    write_export_options(args.export_options, args.destination, os.environ["APPLE_TEAM_ID"], certificate_sha1, profiles)
    print(f"ExportOptions: {args.export_options} (수동 서명, {len(profiles)}개 프로파일)")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    prepare_parser = commands.add_parser("prepare")
    prepare_parser.add_argument("--archive", required=True)
    prepare_parser.add_argument("--out", required=True)
    prepare_parser.add_argument("--destination", choices=["upload", "export"], default="upload")
    prepare_parser.add_argument("--export-options", required=True)
    args = parser.parse_args()
    try:
        prepare(args)
    except ApiError as error:
        fail(str(error))


if __name__ == "__main__":
    main()
