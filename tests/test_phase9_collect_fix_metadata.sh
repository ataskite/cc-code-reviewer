#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase9 metadata.XXXXXX")"
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase9 metadata logs.XXXXXX")"
trap 'rm -rf "$TMP_DIR" "$LOG_DIR"' EXIT

git -C "$TMP_DIR" init -q
git -C "$TMP_DIR" config user.email fixer@example.com
git -C "$TMP_DIR" config user.name "Fix User"
printf 'one\n' > "$TMP_DIR/A.java"
git -C "$TMP_DIR" add A.java
git -C "$TMP_DIR" commit -q -m "first"
git -C "$TMP_DIR" switch -q -c "fix/metadata"

OUTPUT="$(bash "$ROOT_DIR/scripts/phase9-collect-fix-metadata.sh" "$TMP_DIR")"

echo "$OUTPUT" | grep -Fq "FIX_BRANCH=fix/metadata"
echo "$OUTPUT" | grep -Eq "^FIX_COMPLETED_AT=[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} [+-][0-9]{4}$"
echo "$OUTPUT" | grep -Eq "^FIX_COMPLETED_DATE=[0-9]{4}-[0-9]{2}-[0-9]{2}$"
echo "$OUTPUT" | grep -Fq "FIX_ACTOR_NAME=Fix User"
echo "$OUTPUT" | grep -Fq "FIX_ACTOR_EMAIL=fixer@example.com"
echo "$OUTPUT" | grep -Fq "FIX_ACTOR=Fix User <fixer@example.com>"

DETACHED_DIR="$LOG_DIR/detached"
mkdir "$DETACHED_DIR"
git -C "$DETACHED_DIR" init -q
git -C "$DETACHED_DIR" config user.email detached@example.com
git -C "$DETACHED_DIR" config user.name "Detached User"
printf 'one\n' > "$DETACHED_DIR/A.java"
git -C "$DETACHED_DIR" add A.java
git -C "$DETACHED_DIR" commit -q -m "first"
DETACHED_SHA="$(git -C "$DETACHED_DIR" rev-parse --short HEAD)"
git -C "$DETACHED_DIR" switch -q --detach HEAD

DETACHED_OUTPUT="$(bash "$ROOT_DIR/scripts/phase9-collect-fix-metadata.sh" "$DETACHED_DIR")"
echo "$DETACHED_OUTPUT" | grep -Fq "FIX_BRANCH=detached-head:$DETACHED_SHA"

NO_USER_DIR="$LOG_DIR/no-user"
mkdir "$NO_USER_DIR"
git -C "$NO_USER_DIR" init -q
git -C "$NO_USER_DIR" -c user.name="Temp User" -c user.email="temp@example.com" commit --allow-empty -q -m "first"
NO_USER_OUTPUT="$LOG_DIR/no-user.out"
if HOME="$LOG_DIR/empty-home" XDG_CONFIG_HOME="$LOG_DIR/empty-xdg" bash "$ROOT_DIR/scripts/phase9-collect-fix-metadata.sh" "$NO_USER_DIR" >"$NO_USER_OUTPUT" 2>&1; then
  echo "phase9 should fail when git user is not configured" >&2
  exit 1
fi
grep -Fq "当前 Git 用户信息不完整" "$NO_USER_OUTPUT"

NON_GIT_DIR="$LOG_DIR/non-git"
mkdir "$NON_GIT_DIR"
NON_GIT_OUTPUT="$LOG_DIR/non-git.out"
if bash "$ROOT_DIR/scripts/phase9-collect-fix-metadata.sh" "$NON_GIT_DIR" >"$NON_GIT_OUTPUT" 2>&1; then
  echo "phase9 should fail for non-git project" >&2
  exit 1
fi
grep -Fq "当前项目不是 Git 仓库" "$NON_GIT_OUTPUT"
