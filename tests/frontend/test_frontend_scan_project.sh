#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-scan.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

D="$TMP_DIR/app"; mkdir -p "$D/src/components" "$D/src/types"
cat > "$D/package.json" <<'JSON'
{"name":"app","dependencies":{"react":"^18.2.0","react-dom":"^18.2.0","react-router-dom":"^6.0.0"},
 "devDependencies":{"vite":"^5.0.0","typescript":"^5.0.0"}}
JSON
printf 'export const A: number = 1;\n' > "$D/src/a.ts"
printf 'export function C(){return <div/>}\n' > "$D/src/components/C.tsx"
# 根级配置脚本：不得计入正式源码数量（锁定覆盖率口径不变量）
echo 'export default {coverage:true};' > "$D/jest.config.ts"
echo 'declare module "x" { const y: number }' > "$D/src/types/global.d.ts"
cat > "$D/tsconfig.json" <<'JSON'
{"compilerOptions":{"strict":true}}
JSON
cat > "$D/vite.config.ts" <<'TS'
import { defineConfig } from 'vite'; export default defineConfig({})
TS

OUT="$(bash "$ROOT_DIR/scripts/languages/frontend/scan-project.sh" "$D")"

# PROFILE_SCHEMA v1 必备字段
grep -q "PROFILE_SCHEMA_VERSION=1" <<< "$OUT"
grep -q "LANGUAGE_ID=frontend" <<< "$OUT"
grep -q "PROJECT_TYPE=frontend-react" <<< "$OUT"
# package.json 属伴随文件层白名单（filetype-rule-map 可达性），随正式清单计数；
# 根级配置脚本仍由 FORMAL_CONFIG_FILE 单独呈现，不计入 SOURCE_FILE_COUNT。
grep -qE "^SOURCE_FILE_COUNT=3$" <<< "$OUT"
grep -qE "^SOURCE_LINE_COUNT=[1-9]" <<< "$OUT"
# 正式配置单独计数（package.json + tsconfig + vite.config = 3）
grep -qE "^FORMAL_CONFIG_FILE_COUNT=3$" <<< "$OUT"
D_REAL="$(cd "$D" && pwd -P)"
grep -qF "FORMAL_CONFIG_FILE:$D_REAL/package.json" <<< "$OUT"
grep -qF "FORMAL_CONFIG_FILE:$D_REAL/tsconfig.json" <<< "$OUT"
grep -qF "FORMAL_CONFIG_FILE:$D_REAL/vite.config.ts" <<< "$OUT"
# 技术栈行
grep -q "TECH_STACK:React" <<< "$OUT"
# source scope 声明
grep -q "SOURCE_SCOPE:formal|" <<< "$OUT"
grep -q "SOURCE_SCOPE:excluded|node_modules" <<< "$OUT"
# CODE_INTELLIGENCE 占位（detect-code-intelligence.sh 在 Task 4 接入；此处先输出 none 占位）
grep -q "CODE_INTELLIGENCE_PROVIDER=" <<< "$OUT"
# src/components 下有生产源码 → 必须发出至少一条 COMPONENT 行（锁定 emit_components 不漏发）
grep -q "^COMPONENT:components|src/components|" <<< "$OUT"

echo "PASS: frontend scan-project"

W="$TMP_DIR/workspace"; mkdir -p "$W/apps/web/src/components"
cat > "$W/package.json" <<'JSON'
{"name":"root","workspaces":["apps/*"]}
JSON
cat > "$W/apps/web/package.json" <<'JSON'
{"name":"web","dependencies":{"react":"^18.2.0","react-dom":"^18.2.0"}}
JSON
printf 'export function App(){return <div/>}\n' > "$W/apps/web/src/App.tsx"
printf 'export function C(){return <span/>}\n' > "$W/apps/web/src/components/C.tsx"
WOUT="$(bash "$ROOT_DIR/scripts/languages/frontend/scan-project.sh" "$W")"
grep -qE "^SOURCE_FILE_COUNT=3$" <<< "$WOUT"
grep -q "^SOURCE_ROOT:formal|apps/web/src$" <<< "$WOUT"
grep -q "^COMPONENT:components|apps/web/src/components|" <<< "$WOUT"
W_REAL="$(cd "$W" && pwd -P)"
grep -qF "FORMAL_CONFIG_FILE:$W_REAL/apps/web/package.json" <<< "$WOUT"

V="$TMP_DIR/vue2"; mkdir -p "$V/src/components"
cat > "$V/package.json" <<'JSON'
{"name":"legacy","dependencies":{"vue":"^2.6.14","vue-router":"^3.6.5","vuex":"^3.6.2"},
 "devDependencies":{"vue-template-compiler":"^2.6.14","webpack":"^4.46.0",
 "@vue/composition-api":"^1.7.2","vue-class-component":"^7.2.0",
 "vue-property-decorator":"^9.1.2","element-ui":"^2.15.14","ant-design-vue":"^1.7.8"}}
JSON
printf '<template><div>{{ title }}</div></template>\n<script>export default { data(){ return { title: \"x\" } } }</script>\n' > "$V/src/components/Legacy.vue"
printf 'export const api = () => Promise.resolve([])\n' > "$V/src/api.js"
VOUT="$(bash "$ROOT_DIR/scripts/languages/frontend/scan-project.sh" "$V")"
grep -q "PROJECT_TYPE=frontend-vue2" <<< "$VOUT"
grep -qE "^SOURCE_FILE_COUNT=3$" <<< "$VOUT"
grep -q "TECH_STACK:Vue 2" <<< "$VOUT"
grep -q "TECH_STACK:Vue Router" <<< "$VOUT"
grep -q "TECH_STACK:Vuex" <<< "$VOUT"
grep -q "TECH_STACK:Vue2 Composition API" <<< "$VOUT"
grep -q "TECH_STACK:Vue Class Component" <<< "$VOUT"
grep -q "TECH_STACK:Element UI" <<< "$VOUT"
grep -q "TECH_STACK:Ant Design Vue" <<< "$VOUT"
grep -Fq "SOURCE_SCOPE:formal|src/**/*.vue" <<< "$VOUT"

N="$TMP_DIR/node-api"; mkdir -p "$N/src/routes"
cat > "$N/package.json" <<'JSON'
{"name":"api","type":"module","main":"src/server.js","exports":"./src/server.js",
 "engines":{"node":">=18"},"dependencies":{"express":"^4.18.0"}}
JSON
printf 'import express from "express"; export const app = express();\n' > "$N/src/server.js"
printf 'export async function users(){ return [] }\n' > "$N/src/routes/users.js"
NOUT="$(bash "$ROOT_DIR/scripts/languages/frontend/scan-project.sh" "$N")"
grep -q "PROJECT_TYPE=node" <<< "$NOUT"
grep -qE "^SOURCE_FILE_COUNT=3$" <<< "$NOUT"
grep -q "TECH_STACK:Node.js" <<< "$NOUT"
grep -q "TECH_STACK:Express" <<< "$NOUT"
grep -q "RUNTIME_SIGNAL:package.type|module" <<< "$NOUT"
grep -q "RUNTIME_SIGNAL:engines.node|>=18" <<< "$NOUT"

CV="$TMP_DIR/vue-content-only"; mkdir -p "$CV/src"
cat > "$CV/package.json" <<'JSON'
{"name":"content-only"}
JSON
printf 'import { createApp } from "vue"; createApp({}).mount("#app");\n' > "$CV/src/main.ts"
CVOUT="$(bash "$ROOT_DIR/scripts/languages/frontend/scan-project.sh" "$CV")"
grep -q "PROJECT_TYPE=frontend-vue3" <<< "$CVOUT"
grep -qE "^SOURCE_FILE_COUNT=2$" <<< "$CVOUT"
