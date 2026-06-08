#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_FILE="$ROOT_DIR/skills/cc-code-reviewer/SKILL.md"

FULL_REVIEW_LINE="$(grep -n 'label: "全量审查"' "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
if [ -z "$FULL_REVIEW_LINE" ]; then
  echo "missing full review entry option" >&2
  exit 1
fi

FULL_REVIEW_BLOCK="$(sed -n "${FULL_REVIEW_LINE},$((FULL_REVIEW_LINE + 2))p" "$SKILL_FILE")"
if ! printf '%s\n' "$FULL_REVIEW_BLOCK" | grep -Fq 'description: "审查当前分支的全部 Java 代码，适合历史遗留项目或周期性巡检"'; then
  echo "full review entry description must match the approved wording" >&2
  exit 1
fi
