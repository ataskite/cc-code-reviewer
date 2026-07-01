#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-filter.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

W="$TMP_DIR/workspace"
mkdir -p "$W/apps/web/src/components" "$W/apps/web/src/pages" "$W/packages/admin/src/components"
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
echo 'export function C(){return <div/>}' > "$W/apps/web/src/components/C.tsx"
echo 'export function P(){return <div/>}' > "$W/apps/web/src/pages/P.tsx"
echo 'export function A(){return <div/>}' > "$W/packages/admin/src/components/A.jsx"

MANIFEST="$TMP_DIR/manifest.txt"
bash "$ROOT_DIR/scripts/languages/frontend/collect-source-files.sh" "$W" > "$MANIFEST"

OUT="$(bash "$ROOT_DIR/scripts/languages/frontend/filter-source-manifest.sh" "$W" "$MANIFEST" "src/components")"

grep -F "$W/apps/web/src/components/C.tsx" <<< "$OUT"
grep -F "$W/packages/admin/src/components/A.jsx" <<< "$OUT"
! grep -F "$W/apps/web/src/pages/P.tsx" <<< "$OUT"

echo "PASS: frontend filter-source-manifest"
