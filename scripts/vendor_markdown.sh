#!/usr/bin/env bash
# 본문 미리보기에 쓰는 JS(markdown-it, DOMPurify)를 고정 버전으로 받아 DayGrid/Resources/markdown에 넣는다.
# 버전을 올릴 때만 실행한다: scripts/vendor_markdown.sh
set -euo pipefail

MARKDOWN_IT_VERSION=14.1.0
DOMPURIFY_VERSION=3.4.17

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/DayGrid/Resources/markdown"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cd "$work"
npm pack --silent "markdown-it@$MARKDOWN_IT_VERSION" "dompurify@$DOMPURIFY_VERSION" >/dev/null
mkdir markdown-it dompurify
tar xzf "markdown-it-$MARKDOWN_IT_VERSION.tgz" -C markdown-it
tar xzf "dompurify-$DOMPURIFY_VERSION.tgz" -C dompurify

cp markdown-it/package/dist/markdown-it.min.js "$dest/markdown-it.min.js"
cp markdown-it/package/LICENSE "$dest/LICENSE-markdown-it.txt"
cp dompurify/package/dist/purify.min.js "$dest/purify.min.js"
cp dompurify/package/LICENSE "$dest/LICENSE-dompurify.txt"
echo "markdown-it $MARKDOWN_IT_VERSION, DOMPurify $DOMPURIFY_VERSION -> $dest"
