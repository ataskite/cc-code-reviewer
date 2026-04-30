#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase2 branches.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

git -C "$TMP_DIR" init -q
git -C "$TMP_DIR" config user.email test@example.com
git -C "$TMP_DIR" config user.name test

printf 'one\n' > "$TMP_DIR/A.java"
git -C "$TMP_DIR" add A.java
git -C "$TMP_DIR" commit -q -m "first"

CURRENT_BRANCH="$(git -C "$TMP_DIR" branch --show-current)"
git -C "$TMP_DIR" checkout -q -b review-target
git -C "$TMP_DIR" checkout -q "$CURRENT_BRANCH"

OUTPUT="$(bash "$ROOT_DIR/scripts/phase2-detect-branches.sh" "$TMP_DIR")"

echo "$OUTPUT" | grep -q "IS_GIT_REPO=true"
echo "$OUTPUT" | grep -q "CURRENT_BRANCH=$CURRENT_BRANCH"
echo "$OUTPUT" | grep -q "BRANCH: review-target"

SWITCH_OUTPUT="$(bash "$ROOT_DIR/scripts/phase2-switch-branch.sh" "$TMP_DIR" review-target "$CURRENT_BRANCH" local)"
echo "$SWITCH_OUTPUT" | grep -q "已切换到本地分支: review-target"
test "$(git -C "$TMP_DIR" branch --show-current)" = "review-target"

printf 'dirty\n' >> "$TMP_DIR/A.java"
DIRTY_OUTPUT="$TMP_DIR/phase2-dirty.out"
if bash "$ROOT_DIR/scripts/phase2-switch-branch.sh" "$TMP_DIR" "$CURRENT_BRANCH" review-target local >"$DIRTY_OUTPUT" 2>&1; then
  echo "phase2-switch should fail when a local project is dirty" >&2
  exit 1
fi

grep -q "存在未提交改动" "$DIRTY_OUTPUT"
test "$(git -C "$TMP_DIR" branch --show-current)" = "review-target"
