#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# detect-code-intelligence.sh 输出契约测试
D="$TMP_DIR/py-project"; mkdir -p "$D"
echo "" > "$D/pyproject.toml"

OUT="$(bash "$ROOT_DIR/scripts/languages/python/detect-code-intelligence.sh" "$D")"

# 无论是否安装 LSP，都必须输出这些字段
grep -qE 'CODE_INTELLIGENCE_AVAILABLE=(true|false)' <<< "$OUT"
grep -q 'CODE_INTELLIGENCE_LANGUAGE=python' <<< "$OUT"
grep -q 'CODE_INTELLIGENCE_PROVIDER=' <<< "$OUT"

# 若可用，必须有 COMMAND 和 CAPABILITIES
if grep -q 'CODE_INTELLIGENCE_AVAILABLE=true' <<< "$OUT"; then
  grep -q 'CODE_INTELLIGENCE_COMMAND=' <<< "$OUT"
  grep -q 'CODE_INTELLIGENCE_CAPABILITIES=' <<< "$OUT"
  # provider 必须是已知值之一
  PROVIDER="$(grep '^CODE_INTELLIGENCE_PROVIDER=' <<< "$OUT" | cut -d= -f2)"
  case "$PROVIDER" in
    pyright|pylsp|jedi) ;;
    *) echo "FAIL: unknown provider $PROVIDER" >&2; exit 1 ;;
  esac
else
  # 不可用时必须有 REASON
  grep -q 'CODE_INTELLIGENCE_REASON=' <<< "$OUT"
fi

echo "PASS: python detect-code-intelligence"
