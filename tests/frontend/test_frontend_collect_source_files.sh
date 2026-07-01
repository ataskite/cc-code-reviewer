#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-collect.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

D="$TMP_DIR/app"
mkdir -p "$D/src/components" "$D/src/test" "$D/src/types" "$D/dist" "$D/node_modules" "$D/scripts" "$D/tools"
D="$(cd "$D" && pwd -P)"
cat > "$D/package.json" <<'JSON'
{"dependencies":{"react":"^18.2.0"}}
JSON

# 正式生产源码（应被收集）
echo 'export const A: number = 1;' > "$D/src/a.ts"
echo 'export function C(){return <div/>}' > "$D/src/components/C.tsx"
echo 'export const B = 2;' > "$D/src/b.js"

# 必须排除：测试、产物、依赖、根级配置脚本、非 src 目录、.d.ts
echo 'export const T = () => null;' > "$D/src/test/T.test.tsx"
echo 'minified' > "$D/dist/bundle.js"
echo 'module.exports=1' > "$D/node_modules/x.js"
echo "export default {coverage:true};" > "$D/jest.config.ts"
echo "module.exports = {};" > "$D/.eslintrc.js"
echo "export default {};" > "$D/vite.config.ts"
echo "module.exports = {};" > "$D/postcss.config.js"
echo 'export const helper = 1;' > "$D/scripts/build-helper.ts"
echo 'module.exports = 1;' > "$D/tools/codegen.js"
echo 'declare module "x" { const y: number }' > "$D/src/types/global.d.ts"

OUT="$(bash "$ROOT_DIR/scripts/languages/frontend/collect-source-files.sh" "$D")"

# 正式源码必须被收集
grep -F "$D/src/a.ts" <<< "$OUT"
grep -F "$D/src/components/C.tsx" <<< "$OUT"
grep -F "$D/src/b.js" <<< "$OUT"

# 必须排除（负面断言，锁定覆盖率口径不变量）
! grep -F "test/T.test.tsx" <<< "$OUT"
! grep -F "dist/bundle.js" <<< "$OUT"
! grep -F "node_modules/x.js" <<< "$OUT"
# 根级配置脚本不得进入正式源码清单
! grep -F "jest.config.ts" <<< "$OUT"
! grep -F ".eslintrc.js" <<< "$OUT"
! grep -F "vite.config.ts" <<< "$OUT"
! grep -F "postcss.config.js" <<< "$OUT"
# 非 src 目录不得进入正式源码清单
! grep -F "scripts/build-helper.ts" <<< "$OUT"
! grep -F "tools/codegen.js" <<< "$OUT"
# .d.ts 类型声明不得进入正式源码清单
! grep -F "global.d.ts" <<< "$OUT"

echo "PASS: frontend collect-source-files"

# React workspace packages must be collected from package-local src roots,
# not only from PROJECT_DIR/src.
W="$TMP_DIR/workspace"; mkdir -p "$W/apps/web/src" "$W/packages/admin/src"
W="$(cd "$W" && pwd -P)"
cat > "$W/package.json" <<'JSON'
{"name":"root","workspaces":["apps/*","packages/*"]}
JSON
cat > "$W/apps/web/package.json" <<'JSON'
{"dependencies":{"react":"^18.2.0"}}
JSON
cat > "$W/packages/admin/package.json" <<'JSON'
{"dependencies":{"react":"^18.2.0"}}
JSON
echo 'export function App(){return <div/>}' > "$W/apps/web/src/App.tsx"
echo 'export function Admin(){return <div/>}' > "$W/packages/admin/src/Admin.jsx"
WOUT="$(bash "$ROOT_DIR/scripts/languages/frontend/collect-source-files.sh" "$W")"
grep -F "$W/apps/web/src/App.tsx" <<< "$WOUT"
grep -F "$W/packages/admin/src/Admin.jsx" <<< "$WOUT"
