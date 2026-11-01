"""시뮬레이터 녹화(.mov)를 App Store 미리보기 규격으로 바꾼다.

사용법: python3 scripts/appstore/encode_previews.py --raw <녹화 폴더> --out <출력 폴더>

규격(App Store Connect, iPhone 6.9·6.5·6.3형 공통)
- 886x1920 세로, 30fps 이하, H.264 High Profile Level 4.0, 10–12Mbps
- 길이 15–30초: 길면 조금 빠르게 재생하고, 짧으면 마지막 화면을 늘린다.
- 소리: 스테레오 AAC 256kbps 44.1kHz(무음 트랙). 소리 트랙이 없으면 올릴 때 거절될 수 있다.
"""
import argparse
import json
import pathlib
import subprocess
import sys

WIDTH, HEIGHT, FPS = 886, 1920, 30
MIN_SECONDS, MAX_SECONDS = 15.5, 29.5


def duration(path):
    output = subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", str(path)], text=True
    )
    return float(json.loads(output)["format"]["duration"])


def encode(source, target):
    seconds = duration(source)
    filters = []
    if seconds > MAX_SECONDS:
        filters.append(f"setpts=PTS*{MAX_SECONDS / seconds:.5f}")
        final = MAX_SECONDS
    else:
        final = seconds
    filters += [f"fps={FPS}", f"scale={WIDTH}:{HEIGHT}:flags=lanczos", "setsar=1", "format=yuv420p"]
    if final < MIN_SECONDS:
        filters.append(f"tpad=stop_mode=clone:stop_duration={MIN_SECONDS - final:.3f}")
        final = MIN_SECONDS
    command = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-i", str(source),
        "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
        "-map", "0:v:0", "-map", "1:a:0",
        "-vf", ",".join(filters),
        "-c:v", "libx264", "-profile:v", "high", "-level:v", "4.0", "-preset", "slow",
        "-b:v", "10M", "-maxrate", "12M", "-bufsize", "24M",
        "-r", str(FPS),
        "-c:a", "aac", "-b:a", "256k", "-ar", "44100", "-ac", "2",
        "-t", f"{final:.3f}",
        "-movflags", "+faststart",
        str(target),
    ]
    subprocess.run(command, check=True)
    print(f"{target}: 원본 {seconds:.1f}초 → {duration(target):.1f}초, {WIDTH}x{HEIGHT}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    sources = sorted(pathlib.Path(args.raw).glob("*.mov"))
    if not sources:
        print("::warning::녹화 파일이 없습니다")
        return 0
    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    for source in sources:
        if source.stat().st_size == 0:
            print(f"::warning::{source.name}이 비어 있어 건너뜁니다")
            continue
        encode(source, out_dir / f"preview-{source.stem}.mp4")
    return 0


if __name__ == "__main__":
    sys.exit(main())
