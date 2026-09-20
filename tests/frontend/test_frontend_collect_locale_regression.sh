#!/bin/bash
set -euo pipefail

# locale 回归：LC_ALL=C sort 的产物必须由 LC_ALL=C comm 消费。
# 非 C locale（zh_CN.UTF-8）下 comm 按本地 collation 校验输入有序性，
# 对 C 序输入误判「无序」退出 1，set -euo pipefail 放大为脚本终止、空清单。
# 触发文件名对：ayh.js 与 ayh-test.js（C 序 '-'(0x2D) < '.'(0x2E)，
# UTF-8 collation 忽略连字符主权重 → 两种 locale 下相对顺序相反）。
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-collect-locale.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# 目标 locale 不可用时跳过（CI 常见仅 C/POSIX），跳过即视为通过。
if ! locale -a 2>/dev/null | grep -qiE '^zh_CN\.(utf8|UTF-8)$'; then
  echo "SKIP: zh_CN.UTF-8 locale 不可用，locale 回归用例跳过"
  echo "PASS: frontend collect-source-files locale regression"
  exit 0
fi

D="$TMP_DIR/app"
mkdir -p "$D/src/apps"
D="$(cd "$D" && pwd -P)"
cat > "$D/package.json" <<'JSON'
{"dependencies":{"react":"^18.2.0"}}
JSON
echo 'export const A = 1;' > "$D/src/apps/ayh.js"
echo 'export const A2 = 2;' > "$D/src/apps/ayh-test.js"

set +e
OUT="$(LC_ALL=zh_CN.UTF-8 LANG=zh_CN.UTF-8 bash "$ROOT_DIR/scripts/languages/frontend/collect-source-files.sh" "$D" 2>"$TMP_DIR/stderr.txt")"
STATUS=$?
set -e

test "$STATUS" -eq 0
printf '%s\n' "$OUT" | grep -q '/src/apps/ayh\.js$'
printf '%s\n' "$OUT" | grep -q '/src/apps/ayh-test\.js$'
if grep -q '没有被正确排序' "$TMP_DIR/stderr.txt"; then
  echo "FAIL: comm 在 zh_CN.UTF-8 下误判无序" >&2
  exit 1
fi

# 同一清单在 C 与 zh_CN.UTF-8 两种 locale 下必须逐字节一致。
OUT_C="$(LC_ALL=C bash "$ROOT_DIR/scripts/languages/frontend/collect-source-files.sh" "$D" 2>/dev/null)"
test "$OUT" = "$OUT_C"

echo "PASS: frontend collect-source-files locale regression"
