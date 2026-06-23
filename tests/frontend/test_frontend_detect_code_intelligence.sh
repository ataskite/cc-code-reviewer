#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-lsp.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

D="$TMP_DIR/app"; mkdir -p "$D/src"
cat > "$D/package.json" <<'JSON'
{"name":"app","dependencies":{"react":"^18.0.0"}}
JSON
echo 'export const A: number = 1;' > "$D/src/a.ts"
D="$(cd "$D" && pwd -P)"

OUT="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-code-intelligence.sh" "$D")"
grep -q "CODE_INTELLIGENCE_LANGUAGE=frontend" <<< "$OUT"
grep -qE "^CODE_INTELLIGENCE_PROVIDER=(typescript-lsp|none)$" <<< "$OUT"
# 不可用时必须有 reason 与 install hint
grep -q "CODE_INTELLIGENCE_REASON=" <<< "$OUT"
grep -q "CODE_INTELLIGENCE_INSTALL_HINT=" <<< "$OUT"
# provider=none 时 AVAILABLE 必须为 false
if grep -q "^CODE_INTELLIGENCE_PROVIDER=none$" <<< "$OUT"; then
  grep -q "^CODE_INTELLIGENCE_AVAILABLE=false$" <<< "$OUT"
fi

# 项目路径不存在 → 走降级（available=false），不崩溃
set +e
bash "$ROOT_DIR/scripts/languages/frontend/detect-code-intelligence.sh" "$TMP_DIR/nope" >/dev/null 2>&1
RC=$?
set -e
test "$RC" -eq 0

echo "PASS: frontend detect-code-intelligence"
