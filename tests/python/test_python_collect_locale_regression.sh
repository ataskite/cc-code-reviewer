#!/bin/bash
set -euo pipefail

# locale 回归（Python collector）：LC_ALL=C sort 产物必须由 LC_ALL=C comm 消费，
# 否则 zh_CN.UTF-8 下 comm 误判无序退出 1，set -euo pipefail 放大为空清单。
# 触发文件名对：a.py 与 a-x.py（C 序 '-' < '.'，UTF-8 collation 忽略连字符
# → 相对顺序相反）。requirements.txt 使伴随候选非空，完整走 comm 分支。
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/py-collect-locale.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

if ! locale -a 2>/dev/null | grep -qiE '^zh_CN\.(utf8|UTF-8)$'; then
  echo "SKIP: zh_CN.UTF-8 locale 不可用，locale 回归用例跳过"
  echo "PASS: python collect-source-files locale regression"
  exit 0
fi

mkdir -p "$TMP_DIR/app/pkg"
printf 'flask==1.0\n' > "$TMP_DIR/requirements.txt"
printf 'A = 1\n' > "$TMP_DIR/app/pkg/a.py"
printf 'AX = 2\n' > "$TMP_DIR/app/pkg/a-x.py"

set +e
OUT="$(LC_ALL=zh_CN.UTF-8 LANG=zh_CN.UTF-8 bash "$ROOT_DIR/scripts/languages/python/collect-source-files.sh" "$TMP_DIR/app" 2>"$TMP_DIR/stderr.txt")"
STATUS=$?
set -e

test "$STATUS" -eq 0
printf '%s\n' "$OUT" | grep -q '/pkg/a\.py$'
printf '%s\n' "$OUT" | grep -q '/pkg/a-x\.py$'
if grep -q '没有被正确排序' "$TMP_DIR/stderr.txt"; then
  echo "FAIL: comm 在 zh_CN.UTF-8 下误判无序" >&2
  exit 1
fi

OUT_C="$(LC_ALL=C bash "$ROOT_DIR/scripts/languages/python/collect-source-files.sh" "$TMP_DIR/app" 2>/dev/null)"
test "$OUT" = "$OUT_C"

echo "PASS: python collect-source-files locale regression"
