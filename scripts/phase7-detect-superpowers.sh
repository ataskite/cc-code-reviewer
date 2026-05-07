#!/bin/bash
set -euo pipefail

ROOTS="${SUPERPOWERS_SKILL_ROOTS:-$HOME/.agents/skills:$HOME/.codex/skills:$HOME/.codex/skills/.system}"
REQUIRED_SKILLS=(
  "brainstorming"
  "using-git-worktrees"
  "test-driven-development"
  "verification-before-completion"
  "finishing-a-development-branch"
)

missing=()

skill_exists() {
  local skill="$1"
  local root
  local old_ifs="$IFS"

  IFS=':'
  for root in $ROOTS; do
    if [ -z "$root" ]; then
      continue
    fi
    if [ -f "$root/$skill/SKILL.md" ]; then
      IFS="$old_ifs"
      return 0
    fi
  done
  IFS="$old_ifs"
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
