#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/validate-scope.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_DIR="$TMP_DIR/proj"
mkdir -p "$PROJECT_DIR/src/app/sub" "$PROJECT_DIR/node_modules"
mkdir -p "$TMP_DIR/outside"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

# 合法相对路径 → 输出绝对路径，退出 0
OUT="$(bash "$ROOT_DIR/scripts/core/validate-scope.sh" "$PROJECT_DIR" "src/app,src/app/sub")"
grep -F "$PROJECT_DIR/src/app" <<< "$OUT"
grep -F "$PROJECT_DIR/src/app/sub" <<< "$OUT"

# 绝对路径 → 拒绝
set +e
bash "$ROOT_DIR/scripts/core/validate-scope.sh" "$PROJECT_DIR" "/etc/passwd" >/dev/null 2>&1
RC=$?
set -e
test "$RC" -ne 0

# .. 穿越 → 拒绝
set +e
bash "$ROOT_DIR/scripts/core/validate-scope.sh" "$PROJECT_DIR" "../outside" >/dev/null 2>&1
RC=$?
set -e
test "$RC" -ne 0

# 解析后逃逸（符号链接到项目外）→ 拒绝
ln -s "$TMP_DIR/outside" "$PROJECT_DIR/link"
set +e
bash "$ROOT_DIR/scripts/core/validate-scope.sh" "$PROJECT_DIR" "link" >/dev/null 2>&1
RC=$?
set -e
test "$RC" -ne 0

# 空格也作为分隔符（与中文逗号/顿号一致）
SOUT="$(bash "$ROOT_DIR/scripts/core/validate-scope.sh" "$PROJECT_DIR" "src/app src/app/sub")"
grep -F "$PROJECT_DIR/src/app" <<< "$SOUT"
grep -F "$PROJECT_DIR/src/app/sub" <<< "$SOUT"

# 以逻辑路径调用（模拟真实调用方，不做 pwd -P 预规范化）→ 合法路径仍应通过
LOGICAL_DIR="$TMP_DIR/proj"
LOUT="$(bash "$ROOT_DIR/scripts/core/validate-scope.sh" "$LOGICAL_DIR" "src/app")"
grep -F "$PROJECT_DIR/src/app" <<< "$LOUT"

echo "PASS: validate-scope"
