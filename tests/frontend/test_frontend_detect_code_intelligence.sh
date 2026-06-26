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
# provider=none（不可用）时必须有 reason 与 install hint；可用时不输出这两项
if grep -q "^CODE_INTELLIGENCE_PROVIDER=none$" <<< "$OUT"; then
  grep -q "CODE_INTELLIGENCE_REASON=" <<< "$OUT"
  grep -q "CODE_INTELLIGENCE_INSTALL_HINT=" <<< "$OUT"
  grep -q "^CODE_INTELLIGENCE_AVAILABLE=false$" <<< "$OUT"
else
  # provider=typescript-lsp（可用）时必须有 AVAILABLE=true 和 COMMAND
  grep -q "^CODE_INTELLIGENCE_AVAILABLE=true$" <<< "$OUT"
  grep -q "^CODE_INTELLIGENCE_COMMAND=" <<< "$OUT"
fi

# 项目路径不存在 → 走降级（available=false），不崩溃
set +e
bash "$ROOT_DIR/scripts/languages/frontend/detect-code-intelligence.sh" "$TMP_DIR/nope" >/dev/null 2>&1
RC=$?
set -e
test "$RC" -eq 0

echo "PASS: frontend detect-code-intelligence"
