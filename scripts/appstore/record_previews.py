"""UI 테스트(`AppStorePreviewTests`)가 보내는 신호에 맞춰 시뮬레이터 화면을 녹화한다.

사용법: python3 scripts/appstore/record_previews.py --udid <시뮬레이터> --handshake <폴더> --out <폴더>

테스트와 파일로 신호를 주고받는다(`PreviewRecorder`).
1. `<이름>.start`가 생기면 `xcrun simctl io recordVideo`를 시작하고, 녹화가 시작되면 `<이름>.recording`을 만든다.
2. `<이름>.stop`이 생기면 녹화기에 SIGINT를 보내 파일을 마무리하고 `<이름>.saved`를 만든다.
`all.done`이 생기면(워크플로가 테스트를 마친 뒤 만든다) 끝낸다. 녹화 파일은 `<출력>/<이름>.mov`다.

테스트가 중간에 실패하면 `.stop`이 오지 않는다. 그때는 다음 테스트의 `.start`나 `all.done`을 보고 녹화를 끊고,
파일을 `<출력>/aborted/`로 옮겨 미리보기로 쓰지 않게 한다(원인을 볼 수 있게 아티팩트에는 남긴다).
"""
import argparse
import pathlib
import signal
import subprocess
import sys
import threading
import time

# simctl은 첫 녹화를 시작하는 데 30초쯤 걸렸다(2026-11-01 실행 #1). 테스트는 120초까지 기다린다.
START_TIMEOUT = 90
STOP_TIMEOUT = 240
TOTAL_TIMEOUT = 3600


def log(message):
    print(f"[record_previews] {message}", flush=True)


def wait_for_stop(handshake, name, done):
    """`.stop`이 오면 True. 다른 테스트가 시작했거나(`.start`) 모두 끝났으면(`all.done`) False."""
    deadline = time.monotonic() + STOP_TIMEOUT
    while time.monotonic() < deadline:
        if (handshake / f"{name}.stop").exists():
            return True
        if (handshake / "all.done").exists():
            return False
        if any(p.name[: -len(".start")] not in done for p in handshake.glob("*.start")):
            return False
        time.sleep(0.05)
    return False


def record(udid, name, handshake, out_dir, done):
    output = out_dir / f"{name}.mov"
    command = ["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", "--mask=ignored", "--force", str(output)]
    log("시작: " + " ".join(command))
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    started = threading.Event()

    def read_output():
        for line in process.stdout:
            log(f"simctl: {line.rstrip()}")
            if "Recording started" in line:
                started.set()

    reader = threading.Thread(target=read_output, daemon=True)
    reader.start()
    if not started.wait(START_TIMEOUT):
        log(f"'Recording started'를 {START_TIMEOUT}초 안에 보지 못했다. 그대로 진행한다.")
    if process.poll() is not None:
        log(f"녹화기가 바로 끝났다(종료 코드 {process.returncode}).")
    (handshake / f"{name}.recording").touch()

    finished = wait_for_stop(handshake, name, done)
    if process.poll() is None:
        process.send_signal(signal.SIGINT)
        try:
            process.wait(timeout=60)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    reader.join(timeout=5)
    size = output.stat().st_size if output.exists() else 0
    if finished:
        log(f"저장: {output} ({size} bytes)")
    elif output.exists():
        aborted = out_dir / "aborted"
        aborted.mkdir(exist_ok=True)
        output.rename(aborted / output.name)
        log(f"테스트가 끝까지 가지 못해 미리보기로 쓰지 않는다: {aborted / output.name} ({size} bytes)")
    (handshake / f"{name}.saved").touch()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", required=True)
    parser.add_argument("--handshake", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    handshake = pathlib.Path(args.handshake)
    out_dir = pathlib.Path(args.out)
    handshake.mkdir(parents=True, exist_ok=True)
    out_dir.mkdir(parents=True, exist_ok=True)

    done = set()
    deadline = time.monotonic() + TOTAL_TIMEOUT
    while time.monotonic() < deadline:
        for start in sorted(handshake.glob("*.start")):
            name = start.name[: -len(".start")]
            if name not in done:
                done.add(name)
                record(args.udid, name, handshake, out_dir, done)
        if (handshake / "all.done").exists():
            break
        time.sleep(0.1)
    log(f"끝: {', '.join(sorted(done)) or '(녹화 없음)'}")


if __name__ == "__main__":
    sys.exit(main())
