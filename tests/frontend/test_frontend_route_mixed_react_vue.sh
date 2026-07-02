#!/bin/bash
set -euo pipefail
# 【防 P0 回归】React/Vue 信号共存时必须判 Vue 系列，不能被 React 抢占。
# 这是「Vue 完整支持」最核心的回归保护：monorepo 中 react + vue 共存场景。
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-route-mixed.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# 场景 1：react + vue@3 共存 + .vue SFC → 必须 frontend-vue3（不是 react）
D1="$TMP_DIR/mixed_v3"; mkdir -p "$D1/src"
cat > "$D1/package.json" <<'JSON'
{"name":"mixed3","dependencies":{"react":"^18.2.0","vue":"^3.4.0","@vitejs/plugin-vue":"^5.0.0"}}
JSON
echo 'export default function ReactPage(){return null}' > "$D1/src/ReactPage.tsx"
printf '<template><div/></template>\n' > "$D1/src/VueApp.vue"
POUT1="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D1")"
grep -q "PROJECT_TYPE=frontend-vue3" <<< "$POUT1"
! grep -q "PROJECT_TYPE=frontend-react" <<< "$POUT1"

# 场景 2：react + vue@2 + .vue → 必须 frontend-vue2
D2="$TMP_DIR/mixed_v2"; mkdir -p "$D2/src"
cat > "$D2/package.json" <<'JSON'
{"name":"mixed2","dependencies":{"react":"^18.2.0","vue":"^2.7.0","vue-template-compiler":"^2.7.0"}}
JSON
echo 'export default function R(){return null}' > "$D2/src/R.tsx"
printf '<template><span/></template>\n' > "$D2/src/Legacy.vue"
POUT2="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D2")"
grep -q "PROJECT_TYPE=frontend-vue2" <<< "$POUT2"
! grep -q "PROJECT_TYPE=frontend-react" <<< "$POUT2"

# 场景 3：纯 React（无任何 Vue 信号）仍正确判 react（确认 Vue 优先不误伤纯 React）
D3="$TMP_DIR/pure_react"; mkdir -p "$D3/src"
cat > "$D3/package.json" <<'JSON'
{"name":"pure","dependencies":{"react":"^18.2.0","react-dom":"^18.2.0"}}
JSON
echo 'export default function App(){return <div/>}' > "$D3/src/App.tsx"
POUT3="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D3")"
grep -q "PROJECT_TYPE=frontend-react" <<< "$POUT3"

echo "PASS: frontend route mixed react+vue (vue wins)"
