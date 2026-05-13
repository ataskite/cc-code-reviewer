#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase7 superpowers.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SKILL_ROOT="$TMP_DIR/skills"
mkdir -p "$SKILL_ROOT/brainstorming" "$SKILL_ROOT/test-driven-development" "$SKILL_ROOT/verification-before-completion"
printf '# brainstorming\n' >"$SKILL_ROOT/brainstorming/SKILL.md"
printf '# tdd\n' >"$SKILL_ROOT/test-driven-development/SKILL.md"
printf '# verification\n' >"$SKILL_ROOT/verification-before-completion/SKILL.md"

OUTPUT="$(SUPERPOWERS_SKILL_ROOTS="$SKILL_ROOT" bash "$ROOT_DIR/scripts/phase7-detect-superpowers.sh")"
echo "$OUTPUT" | grep -Fq "SUPERPOWERS_AVAILABLE=false"
echo "$OUTPUT" | grep -Fq "SUPERPOWER_SKILL:brainstorming=available"
echo "$OUTPUT" | grep -Fq "SUPERPOWER_SKILL:test-driven-development=available"
echo "$OUTPUT" | grep -Fq "SUPERPOWER_SKILL:using-git-worktrees=missing"
echo "$OUTPUT" | grep -Fq "SUPERPOWER_SKILL:subagent-driven-development=missing"
echo "$OUTPUT" | grep -Fq "SUPERPOWER_MISSING=using-git-worktrees,finishing-a-development-branch,subagent-driven-development"

mkdir -p "$SKILL_ROOT/using-git-worktrees" "$SKILL_ROOT/finishing-a-development-branch" "$SKILL_ROOT/subagent-driven-development"
printf '# worktrees\n' >"$SKILL_ROOT/using-git-worktrees/SKILL.md"
printf '# finishing\n' >"$SKILL_ROOT/finishing-a-development-branch/SKILL.md"
printf '# subagent-driven\n' >"$SKILL_ROOT/subagent-driven-development/SKILL.md"

FULL_OUTPUT="$(SUPERPOWERS_SKILL_ROOTS="$SKILL_ROOT" bash "$ROOT_DIR/scripts/phase7-detect-superpowers.sh")"
echo "$FULL_OUTPUT" | grep -Fq "SUPERPOWERS_AVAILABLE=true"
echo "$FULL_OUTPUT" | grep -Fq "SUPERPOWER_MISSING=none"

FIRST_ROOT="$TMP_DIR/first skills"
SECOND_ROOT="$TMP_DIR/second skills"
mkdir -p "$FIRST_ROOT/brainstorming" "$FIRST_ROOT/test-driven-development" "$SECOND_ROOT/using-git-worktrees" "$SECOND_ROOT/verification-before-completion" "$SECOND_ROOT/finishing-a-development-branch" "$SECOND_ROOT/subagent-driven-development"
printf '# brainstorming\n' >"$FIRST_ROOT/brainstorming/SKILL.md"
printf '# tdd\n' >"$FIRST_ROOT/test-driven-development/SKILL.md"
printf '# worktrees\n' >"$SECOND_ROOT/using-git-worktrees/SKILL.md"
printf '# verification\n' >"$SECOND_ROOT/verification-before-completion/SKILL.md"
printf '# finishing\n' >"$SECOND_ROOT/finishing-a-development-branch/SKILL.md"
printf '# subagent-driven\n' >"$SECOND_ROOT/subagent-driven-development/SKILL.md"

COLON_OUTPUT="$(SUPERPOWERS_SKILL_ROOTS="$FIRST_ROOT:$SECOND_ROOT" bash "$ROOT_DIR/scripts/phase7-detect-superpowers.sh")"
echo "$COLON_OUTPUT" | grep -Fq "SUPERPOWERS_AVAILABLE=true"
echo "$COLON_OUTPUT" | grep -Fq "SUPERPOWER_MISSING=none"

EMPTY_PART_OUTPUT="$(SUPERPOWERS_SKILL_ROOTS="$FIRST_ROOT::$SECOND_ROOT:" bash "$ROOT_DIR/scripts/phase7-detect-superpowers.sh")"
echo "$EMPTY_PART_OUTPUT" | grep -Fq "SUPERPOWERS_AVAILABLE=true"
echo "$EMPTY_PART_OUTPUT" | grep -Fq "SUPERPOWER_MISSING=none"

GLOB_ROOT="$TMP_DIR/skills[abc]"
GLOB_EXPANSION_ROOT="$TMP_DIR/skillsa"
mkdir -p "$GLOB_ROOT/brainstorming" "$GLOB_ROOT/using-git-worktrees" "$GLOB_ROOT/test-driven-development" "$GLOB_ROOT/verification-before-completion" "$GLOB_ROOT/finishing-a-development-branch" "$GLOB_ROOT/subagent-driven-development" "$GLOB_EXPANSION_ROOT"
printf '# brainstorming\n' >"$GLOB_ROOT/brainstorming/SKILL.md"
printf '# worktrees\n' >"$GLOB_ROOT/using-git-worktrees/SKILL.md"
printf '# tdd\n' >"$GLOB_ROOT/test-driven-development/SKILL.md"
printf '# verification\n' >"$GLOB_ROOT/verification-before-completion/SKILL.md"
printf '# finishing\n' >"$GLOB_ROOT/finishing-a-development-branch/SKILL.md"
printf '# subagent-driven\n' >"$GLOB_ROOT/subagent-driven-development/SKILL.md"

GLOB_OUTPUT="$(SUPERPOWERS_SKILL_ROOTS="$GLOB_ROOT" bash "$ROOT_DIR/scripts/phase7-detect-superpowers.sh")"
echo "$GLOB_OUTPUT" | grep -Fq "SUPERPOWERS_AVAILABLE=true"
echo "$GLOB_OUTPUT" | grep -Fq "SUPERPOWER_MISSING=none"
