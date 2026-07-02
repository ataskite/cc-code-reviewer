#!/bin/bash
set -euo pipefail
# 【防 P0 回归】Vue3 依赖被 hoist（该 package 顶层无 "vue"，只有 @vitejs/plugin-vue/pinia）时：
#   1. detect-project.sh 仍能识别为 frontend-vue3
#   2. collect-source-files.sh 源码清单非空（不再静默零覆盖）
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-route-hoisted.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# package 顶层无 "vue"，只有 vue 相关工具链包（模拟 pnpm/npm hoisting）
D="$TMP_DIR/hoisted"; mkdir -p "$D/src"
cat > "$D/package.json" <<'JSON'
{"name":"hoisted-pkg","dependencies":{"@vitejs/plugin-vue":"^5.0.0","pinia":"^2.1.0"}}
JSON
printf '<template><div>{{ count }}</div></template>\n<script setup>\nconst count = 1\n</script>\n' > "$D/src/App.vue"
echo 'export const useStore = () => 1' > "$D/src/store.ts"

# 1. 识别为 vue3
POUT="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D")"
grep -q "PROJECT_TYPE=frontend-vue3" <<< "$POUT"

# 2. 源码清单非空（关键：旧实现因 has_vue_dep 只认 "vue" key 会返回空清单）
MANIFEST="$(bash "$ROOT_DIR/scripts/languages/frontend/collect-source-files.sh" "$D")"
LINES="$(printf '%s\n' "$MANIFEST" | grep -c . || true)"
[ "$LINES" -ge 2 ] || { echo "FAIL: hoisted vue3 manifest empty ($LINES lines)" >&2; exit 1; }
printf '%s\n' "$MANIFEST" | grep -q "App.vue"
printf '%s\n' "$MANIFEST" | grep -q "store.ts"

# 3. scan-project 文件计数 > 0
SOUT="$(bash "$ROOT_DIR/scripts/languages/frontend/scan-project.sh" "$D")"
FILE_COUNT="$(printf '%s\n' "$SOUT" | sed -n 's/^SOURCE_FILE_COUNT=//p' | head -1)"
[ "$FILE_COUNT" -ge 2 ] || { echo "FAIL: SOURCE_FILE_COUNT=$FILE_COUNT < 2" >&2; exit 1; }

echo "PASS: frontend route vue3 hoisted deps (manifest non-empty)"
