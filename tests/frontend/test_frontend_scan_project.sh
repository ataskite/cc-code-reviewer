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
grep -qE "^SOURCE_FILE_COUNT=2$" <<< "$OUT"
grep -qE "^SOURCE_LINE_COUNT=[1-9]" <<< "$OUT"
# 正式配置单独计数（package.json + tsconfig + vite.config = 3）
grep -qE "^FORMAL_CONFIG_FILE_COUNT=3$" <<< "$OUT"
# 技术栈行
grep -q "TECH_STACK:React" <<< "$OUT"
# source scope 声明
grep -q "SOURCE_SCOPE:formal|" <<< "$OUT"
grep -q "SOURCE_SCOPE:excluded|node_modules" <<< "$OUT"
# CODE_INTELLIGENCE 占位（detect-code-intelligence.sh 在 Task 4 接入；此处先输出 none 占位）
grep -q "CODE_INTELLIGENCE_PROVIDER=" <<< "$OUT"

echo "PASS: frontend scan-project"
