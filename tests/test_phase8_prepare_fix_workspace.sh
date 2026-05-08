#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase8 workspace.XXXXXX")"
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase8 workspace logs.XXXXXX")"
trap 'rm -rf "$TMP_DIR" "$LOG_DIR"' EXIT

PS1_FILE="$ROOT_DIR/scripts/phase8-prepare-fix-workspace.ps1"
PS1_EXISTING_LINE="$(grep -n '修复 worktree 已存在' "$PS1_FILE" | cut -d: -f1)"
PS1_DIRTY_LINE="$(grep -n '不能从脏工作区创建修复 worktree' "$PS1_FILE" | cut -d: -f1)"
PS1_IGNORE_LINE="$(grep -n 'Ensure-WorktreesIgnored' "$PS1_FILE" | tail -1 | cut -d: -f1)"
test "$PS1_EXISTING_LINE" -lt "$PS1_IGNORE_LINE"
test "$PS1_DIRTY_LINE" -lt "$PS1_IGNORE_LINE"

git -C "$TMP_DIR" init -q
git -C "$TMP_DIR" config user.email test@example.com
git -C "$TMP_DIR" config user.name test
printf 'one\n' > "$TMP_DIR/A.java"
git -C "$TMP_DIR" add A.java
git -C "$TMP_DIR" commit -q -m "first"

CURRENT_BRANCH="$(git -C "$TMP_DIR" branch --show-current)"

CURRENT_OUTPUT="$(bash "$ROOT_DIR/scripts/phase8-prepare-fix-workspace.sh" "$TMP_DIR" current "")"
echo "$CURRENT_OUTPUT" | grep -q "FIX_WORKSPACE_MODE=current"
echo "$CURRENT_OUTPUT" | grep -q "FIX_WORKSPACE_PATH=$TMP_DIR"
echo "$CURRENT_OUTPUT" | grep -q "FIX_BRANCH=$CURRENT_BRANCH"

BRANCH_OUTPUT="$(bash "$ROOT_DIR/scripts/phase8-prepare-fix-workspace.sh" "$TMP_DIR" branch "fix/review-findings")"
echo "$BRANCH_OUTPUT" | grep -q "FIX_WORKSPACE_MODE=branch"
echo "$BRANCH_OUTPUT" | grep -q "FIX_WORKSPACE_PATH=$TMP_DIR"
echo "$BRANCH_OUTPUT" | grep -q "FIX_BRANCH=fix/review-findings"
test "$(git -C "$TMP_DIR" branch --show-current)" = "fix/review-findings"

git -C "$TMP_DIR" switch -q "$CURRENT_BRANCH"

WORKTREE_OUTPUT="$(bash "$ROOT_DIR/scripts/phase8-prepare-fix-workspace.sh" "$TMP_DIR" worktree "fix/worktree-findings")"
echo "$WORKTREE_OUTPUT" | grep -q "FIX_WORKSPACE_MODE=worktree"
echo "$WORKTREE_OUTPUT" | grep -q "FIX_WORKSPACE_PATH=$TMP_DIR/.worktrees/fix/worktree-findings"
echo "$WORKTREE_OUTPUT" | grep -q "FIX_BRANCH=fix/worktree-findings"
echo "$WORKTREE_OUTPUT" | grep -q "FIX_WORKTREE_PROJECT=$(basename "$TMP_DIR")"
test -e "$TMP_DIR/.worktrees/fix/worktree-findings/.git"
test "$(git -C "$TMP_DIR/.worktrees/fix/worktree-findings" branch --show-current)" = "fix/worktree-findings"
test -z "$(git -C "$TMP_DIR" status --porcelain)"

WORKTREE_EXISTS_OUTPUT="$LOG_DIR/phase8-worktree-exists.out"
if bash "$ROOT_DIR/scripts/phase8-prepare-fix-workspace.sh" "$TMP_DIR" worktree "fix/worktree-findings" >"$WORKTREE_EXISTS_OUTPUT" 2>&1; then
  echo "phase8 should fail when requested worktree exists" >&2
  exit 1
fi
grep -q "修复 worktree 已存在" "$WORKTREE_EXISTS_OUTPUT"

git -C "$TMP_DIR" worktree remove -f "$TMP_DIR/.worktrees/fix/worktree-findings"

git -C "$TMP_DIR" branch "fix/existing-worktree"
EXISTING_WORKTREE_OUTPUT="$(bash "$ROOT_DIR/scripts/phase8-prepare-fix-workspace.sh" "$TMP_DIR" worktree "fix/existing-worktree")"
echo "$EXISTING_WORKTREE_OUTPUT" | grep -q "FIX_WORKSPACE_MODE=worktree"
echo "$EXISTING_WORKTREE_OUTPUT" | grep -q "FIX_WORKSPACE_PATH=$TMP_DIR/.worktrees/fix/existing-worktree"
echo "$EXISTING_WORKTREE_OUTPUT" | grep -q "FIX_BRANCH=fix/existing-worktree"
test "$(git -C "$TMP_DIR/.worktrees/fix/existing-worktree" branch --show-current)" = "fix/existing-worktree"
test -z "$(git -C "$TMP_DIR" status --porcelain)"
git -C "$TMP_DIR" worktree remove -f "$TMP_DIR/.worktrees/fix/existing-worktree"

printf 'dirty\n' >> "$TMP_DIR/A.java"

DIRTY_BRANCH_OUTPUT="$LOG_DIR/phase8-dirty-branch.out"
if bash "$ROOT_DIR/scripts/phase8-prepare-fix-workspace.sh" "$TMP_DIR" branch "fix/dirty" >"$DIRTY_BRANCH_OUTPUT" 2>&1; then
  echo "phase8 should fail on dirty branch strategy" >&2
  exit 1
fi
grep -q "存在未提交改动" "$DIRTY_BRANCH_OUTPUT"

DIRTY_WORKTREE_OUTPUT="$LOG_DIR/phase8-dirty-worktree.out"
if bash "$ROOT_DIR/scripts/phase8-prepare-fix-workspace.sh" "$TMP_DIR" worktree "fix/dirty-worktree" >"$DIRTY_WORKTREE_OUTPUT" 2>&1; then
  echo "phase8 should fail on dirty worktree strategy" >&2
  exit 1
fi
grep -q "存在未提交改动" "$DIRTY_WORKTREE_OUTPUT"

git -C "$TMP_DIR" checkout -q -- A.java

INVALID_OUTPUT="$LOG_DIR/phase8-invalid.out"
if bash "$ROOT_DIR/scripts/phase8-prepare-fix-workspace.sh" "$TMP_DIR" branch "bad branch name" >"$INVALID_OUTPUT" 2>&1; then
  echo "phase8 should fail for invalid branch name" >&2
  exit 1
fi
grep -q "非法修复分支名" "$INVALID_OUTPUT"

EMPTY_BRANCH_OUTPUT="$LOG_DIR/phase8-empty-branch.out"
if bash "$ROOT_DIR/scripts/phase8-prepare-fix-workspace.sh" "$TMP_DIR" branch "" >"$EMPTY_BRANCH_OUTPUT" 2>&1; then
  echo "phase8 should fail for empty branch name" >&2
  exit 1
fi
grep -q "修复分支名不能为空" "$EMPTY_BRANCH_OUTPUT"

MISSING_PROJECT_OUTPUT="$LOG_DIR/phase8-missing-project.out"
if bash "$ROOT_DIR/scripts/phase8-prepare-fix-workspace.sh" "$TMP_DIR/missing" current "" >"$MISSING_PROJECT_OUTPUT" 2>&1; then
  echo "phase8 should fail for missing project path" >&2
  exit 1
fi
grep -q "项目路径不存在" "$MISSING_PROJECT_OUTPUT"

NON_GIT_DIR="$LOG_DIR/non-git"
mkdir "$NON_GIT_DIR"
NON_GIT_OUTPUT="$LOG_DIR/phase8-non-git.out"
if bash "$ROOT_DIR/scripts/phase8-prepare-fix-workspace.sh" "$NON_GIT_DIR" current "" >"$NON_GIT_OUTPUT" 2>&1; then
  echo "phase8 should fail for non-git project" >&2
  exit 1
fi
grep -q "当前项目不是 Git 仓库" "$NON_GIT_OUTPUT"

UNKNOWN_MODE_OUTPUT="$LOG_DIR/phase8-unknown-mode.out"
if bash "$ROOT_DIR/scripts/phase8-prepare-fix-workspace.sh" "$TMP_DIR" unknown "fix/unknown" >"$UNKNOWN_MODE_OUTPUT" 2>&1; then
  echo "phase8 should fail for unknown workspace strategy" >&2
  exit 1
fi
grep -q "未知工作区策略" "$UNKNOWN_MODE_OUTPUT"

EXISTING_MUTATION_DIR="$LOG_DIR/existing-mutation"
mkdir "$EXISTING_MUTATION_DIR"
git -C "$EXISTING_MUTATION_DIR" init -q
git -C "$EXISTING_MUTATION_DIR" config user.email test@example.com
git -C "$EXISTING_MUTATION_DIR" config user.name test
printf 'one\n' > "$EXISTING_MUTATION_DIR/A.java"
git -C "$EXISTING_MUTATION_DIR" add A.java
git -C "$EXISTING_MUTATION_DIR" commit -q -m "first"
mkdir -p "$EXISTING_MUTATION_DIR/.worktrees/fix/existing"
EXISTING_MUTATION_EXCLUDE="$(git -C "$EXISTING_MUTATION_DIR" rev-parse --git-path info/exclude)"
EXISTING_MUTATION_BEFORE="$(cat "$EXISTING_MUTATION_EXCLUDE" 2>/dev/null || true)"
EXISTING_MUTATION_OUTPUT="$LOG_DIR/phase8-existing-mutation.out"
if bash "$ROOT_DIR/scripts/phase8-prepare-fix-workspace.sh" "$EXISTING_MUTATION_DIR" worktree "fix/existing" >"$EXISTING_MUTATION_OUTPUT" 2>&1; then
  echo "phase8 should fail when pre-existing worktree path exists" >&2
  exit 1
fi
grep -q "修复 worktree 已存在" "$EXISTING_MUTATION_OUTPUT"
EXISTING_MUTATION_AFTER="$(cat "$EXISTING_MUTATION_EXCLUDE" 2>/dev/null || true)"
test "$EXISTING_MUTATION_AFTER" = "$EXISTING_MUTATION_BEFORE"

DIRTY_MUTATION_DIR="$LOG_DIR/dirty-mutation"
mkdir "$DIRTY_MUTATION_DIR"
git -C "$DIRTY_MUTATION_DIR" init -q
git -C "$DIRTY_MUTATION_DIR" config user.email test@example.com
git -C "$DIRTY_MUTATION_DIR" config user.name test
printf 'one\n' > "$DIRTY_MUTATION_DIR/A.java"
git -C "$DIRTY_MUTATION_DIR" add A.java
git -C "$DIRTY_MUTATION_DIR" commit -q -m "first"
printf 'dirty\n' >> "$DIRTY_MUTATION_DIR/A.java"
DIRTY_MUTATION_EXCLUDE="$(git -C "$DIRTY_MUTATION_DIR" rev-parse --git-path info/exclude)"
DIRTY_MUTATION_BEFORE="$(cat "$DIRTY_MUTATION_EXCLUDE" 2>/dev/null || true)"
DIRTY_MUTATION_OUTPUT="$LOG_DIR/phase8-dirty-mutation.out"
if bash "$ROOT_DIR/scripts/phase8-prepare-fix-workspace.sh" "$DIRTY_MUTATION_DIR" worktree "fix/dirty" >"$DIRTY_MUTATION_OUTPUT" 2>&1; then
  echo "phase8 should fail on dirty worktree strategy before mutating exclude" >&2
  exit 1
fi
grep -q "存在未提交改动" "$DIRTY_MUTATION_OUTPUT"
DIRTY_MUTATION_AFTER="$(cat "$DIRTY_MUTATION_EXCLUDE" 2>/dev/null || true)"
test "$DIRTY_MUTATION_AFTER" = "$DIRTY_MUTATION_BEFORE"
