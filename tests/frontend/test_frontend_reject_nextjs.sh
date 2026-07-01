#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-nx.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

D="$TMP_DIR/next"; mkdir -p "$D/src/app"
cat > "$D/package.json" <<'JSON'
{"name":"n","dependencies":{"next":"^14.0.0","react":"^18.0.0"}}
JSON
echo 'export default function P(){return <div/>}' > "$D/src/app/page.tsx"

# detect-project 必须标记不支持，不能套用 React 规则
OUT="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D")"
grep -q "PROJECT_TYPE=frontend-unsupported" <<< "$OUT"
grep -q "reason=nextjs" <<< "$OUT"

# scan-project 仍然输出 PROFILE（但 PROJECT_TYPE 为 unsupported）
SOUT="$(bash "$ROOT_DIR/scripts/languages/frontend/scan-project.sh" "$D" 2>&1 || true)"
grep -q "PROJECT_TYPE=frontend-unsupported" <<< "$SOUT"

echo "PASS: frontend reject nextjs"
