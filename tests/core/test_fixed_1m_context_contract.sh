#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL_FILE="$ROOT_DIR/skills/cc-code-reviewer/SKILL.md"

test ! -e "$ROOT_DIR/scripts/core/detect-model-context.sh"
test ! -e "$ROOT_DIR/tests/test_phase14_detect_model_context.sh"

if rg -q 'detect-model-context|CC_REVIEW_CONTEXT_SCALE|default_fallback|200k 窗口|200K 窗口' \
  "$SKILL_FILE" \
  "$ROOT_DIR/AGENTS.md" \
  "$ROOT_DIR/CLAUDE.md" \
  "$ROOT_DIR/agents/cc-code-reviewer.md" \
  "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"; then
  echo "active scan contracts must not contain dynamic context detection or 200k fallback" >&2
  exit 1
fi

grep -q 'CONTEXT_WINDOW_TOKENS=1000000' "$SKILL_FILE"
grep -q 'CONTEXT_SCALE=5' "$SKILL_FILE"
grep -q '固定 1M' "$SKILL_FILE"

echo "PASS: fixed 1M context contract"
