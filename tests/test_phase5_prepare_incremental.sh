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

OUTPUT="$(bash "$ROOT_DIR/scripts/core/prepare-incremental.sh" "$TMP_DIR" 2)"

echo "$OUTPUT" | grep -q "# === 提交记录 ==="
echo "$OUTPUT" | grep -q "# === 变更文件列表 ==="
echo "$OUTPUT" | grep -q "^A.java$"
echo "$OUTPUT" | grep -q "# === 变更统计 ==="

# SHA-256 仓库覆盖根提交时必须动态使用对应对象格式的空 tree OID。
SHA256_DIR="$TMP_DIR/sha256"
if git init -q --object-format=sha256 "$SHA256_DIR" 2>/dev/null; then
  git -C "$SHA256_DIR" config user.email test@example.com
  git -C "$SHA256_DIR" config user.name test
  printf 'sha256\n' > "$SHA256_DIR/Root.java"
  git -C "$SHA256_DIR" add Root.java
  git -C "$SHA256_DIR" commit -q -m "root"
  SHA256_OUTPUT="$(bash "$ROOT_DIR/scripts/core/prepare-incremental.sh" "$SHA256_DIR" 1)"
  echo "$SHA256_OUTPUT" | grep -q '^Root.java$'
  echo "$SHA256_OUTPUT" | grep -q '1 file changed, 1 insertion'
fi
