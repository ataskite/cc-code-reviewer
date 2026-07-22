#!/bin/bash
# Superpowers 能力检测（可选，仅用于 fix 阶段 Superpowers 路线）。
#
# 平台中立：Skill 搜索根覆盖 Claude Code / Codex / ZCode / 通用 .agents 四端，
# 不偏向任一平台。SUPERPOWERS_SKILL_ROOTS 可覆盖默认搜索路径。
set -euo pipefail

ROOTS="${SUPERPOWERS_SKILL_ROOTS:-$HOME/.agents/skills:$HOME/.codex/skills:$HOME/.codex/skills/.system:$HOME/.claude/skills:$HOME/.zcode/skills}"
REQUIRED_SKILLS=(
  "brainstorming"
  "using-git-worktrees"
  "test-driven-development"
  "verification-before-completion"
  "finishing-a-development-branch"
  "subagent-driven-development"
)

missing=()
IFS=':' read -r -a roots <<<"$ROOTS"

skill_exists() {
  local skill="$1"
  local root

  for root in "${roots[@]}"; do
    if [ -z "$root" ]; then
      continue
    fi
    if [ -f "$root/$skill/SKILL.md" ]; then
      return 0
    fi
  done
  return 1
}

for skill in "${REQUIRED_SKILLS[@]}"; do
  if skill_exists "$skill"; then
    echo "SUPERPOWER_SKILL:$skill=available"
  else
    echo "SUPERPOWER_SKILL:$skill=missing"
    missing+=("$skill")
  fi
done

if [ "${#missing[@]}" -eq 0 ]; then
  echo "SUPERPOWERS_AVAILABLE=true"
  echo "SUPERPOWER_MISSING=none"
else
  echo "SUPERPOWERS_AVAILABLE=false"
  IFS=','
  echo "SUPERPOWER_MISSING=${missing[*]}"
fi
