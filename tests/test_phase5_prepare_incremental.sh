#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase5 incremental.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

git -C "$TMP_DIR" init -q
git -C "$TMP_DIR" config user.email test@example.com
git -C "$TMP_DIR" config user.name test

printf 'one\n' > "$TMP_DIR/A.java"
git -C "$TMP_DIR" add A.java
git -C "$TMP_DIR" commit -q -m "first"

printf 'two\n' >> "$TMP_DIR/A.java"
git -C "$TMP_DIR" add A.java
git -C "$TMP_DIR" commit -q -m "second"

OUTPUT="$(bash "$ROOT_DIR/scripts/phase5-prepare-incremental.sh" "$TMP_DIR" 2)"

echo "$OUTPUT" | grep -q "# === 提交记录 ==="
echo "$OUTPUT" | grep -q "# === 变更文件列表 ==="
echo "$OUTPUT" | grep -q "^A.java$"
echo "$OUTPUT" | grep -q "# === 变更统计 ==="
