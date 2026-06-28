#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase5 preview.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

git -C "$TMP_DIR" init -q
git -C "$TMP_DIR" config user.email test@example.com
git -C "$TMP_DIR" config user.name test

for i in $(seq 1 12); do
  printf 'commit %s\n' "$i" >> "$TMP_DIR/A.java"
  git -C "$TMP_DIR" add A.java
  git -C "$TMP_DIR" commit -q -m "message $i"
done

OUTPUT="$(bash "$ROOT_DIR/scripts/core/preview-recent-commits.sh" "$TMP_DIR")"

echo "$OUTPUT" | grep -q "# === 最近提交预览 ==="
echo "$OUTPUT" | grep -Eq '^1\. [0-9a-f]+ message 12$'
echo "$OUTPUT" | grep -Eq '^10\. [0-9a-f]+ message 3$'
if echo "$OUTPUT" | grep -q "message 2"; then
  echo "preview should only include the 10 most recent commits" >&2
  exit 1
fi
