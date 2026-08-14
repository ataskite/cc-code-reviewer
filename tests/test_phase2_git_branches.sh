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

OUTPUT="$(bash "$ROOT_DIR/scripts/core/detect-branches.sh" "$TMP_DIR")"

echo "$OUTPUT" | grep -q "IS_GIT_REPO=true"
echo "$OUTPUT" | grep -q "CURRENT_BRANCH=$CURRENT_BRANCH"
echo "$OUTPUT" | grep -q "BRANCH: review-target"

SWITCH_OUTPUT="$(bash "$ROOT_DIR/scripts/core/switch-branch.sh" "$TMP_DIR" review-target "$CURRENT_BRANCH" local)"
echo "$SWITCH_OUTPUT" | grep -q "已切换到本地分支: review-target"
test "$(git -C "$TMP_DIR" branch --show-current)" = "review-target"

printf 'dirty\n' >> "$TMP_DIR/A.java"
DIRTY_OUTPUT="$TMP_DIR/phase2-dirty.out"
if bash "$ROOT_DIR/scripts/core/switch-branch.sh" "$TMP_DIR" "$CURRENT_BRANCH" review-target local >"$DIRTY_OUTPUT" 2>&1; then
  echo "switch-branch should fail when a local project is dirty" >&2
  exit 1
fi

grep -q "存在未提交改动" "$DIRTY_OUTPUT"
test "$(git -C "$TMP_DIR" branch --show-current)" = "review-target"

# 回归：分支数 > 5 时，detect-branches.sh 必须退出码 0、只展示 5 个分支、并给出总数提示。
# 旧实现用 "git for-each-ref | head -5"，大仓输出超过管道缓冲时 git 收到 SIGPIPE(141)，
# 在 set -e 下导致脚本异常退出（Linux 大仓复现）。这里用 --count=5 在 git 层面限量。
MANY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase2 many.XXXXXX")"
trap 'rm -rf "$TMP_DIR" "$MANY_DIR"' EXIT
git -C "$MANY_DIR" init -q
git -C "$MANY_DIR" config user.email test@example.com
git -C "$MANY_DIR" config user.name test
printf 'one\n' > "$MANY_DIR/A.java"
git -C "$MANY_DIR" add A.java
git -C "$MANY_DIR" commit -q -m "first"
for i in 1 2 3 4 5 6 7 8; do git -C "$MANY_DIR" branch "br$i" >/dev/null; done

set +e
MANY_OUTPUT="$(bash "$ROOT_DIR/scripts/core/detect-branches.sh" "$MANY_DIR" 2>&1)"
MANY_RC=$?
set -e

test "$MANY_RC" -eq 0
echo "$MANY_OUTPUT" | grep -q "IS_GIT_REPO=true"
# 恰好 5 条 BRANCH 行（git --count=5 限量，不再依赖 head）
test "$(echo "$MANY_OUTPUT" | grep -c '^BRANCH: ')" -eq 5
# 总数提示：9 个本地分支（master + 8）
echo "$MANY_OUTPUT" | grep -q "共 9 个本地分支，仅展示最近 5 个"
