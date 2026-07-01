#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:-}"

if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
  echo "项目路径不存在: $PROJECT_DIR" >&2
  exit 1
fi

if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "当前项目不是 Git 仓库，无法采集修复元数据" >&2
  exit 1
fi

FIX_BRANCH="$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || true)"
if [ -z "$FIX_BRANCH" ]; then
  FIX_SHA="$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || true)"
  if [ -n "$FIX_SHA" ]; then
    FIX_BRANCH="detached-head:$FIX_SHA"
  else
    FIX_BRANCH="detached-head"
  fi
fi

FIX_ACTOR_NAME="$(git -C "$PROJECT_DIR" config user.name 2>/dev/null || true)"
FIX_ACTOR_EMAIL="$(git -C "$PROJECT_DIR" config user.email 2>/dev/null || true)"

if [ -z "$FIX_ACTOR_NAME" ] || [ -z "$FIX_ACTOR_EMAIL" ]; then
  echo "当前 Git 用户信息不完整，请先配置 git config user.name 和 git config user.email" >&2
  exit 1
fi

FIX_COMPLETED_AT="$(date '+%Y-%m-%d %H:%M:%S %z')"
FIX_COMPLETED_DATE="$(date '+%Y-%m-%d')"

echo "FIX_COMPLETED_AT=$FIX_COMPLETED_AT"
echo "FIX_COMPLETED_DATE=$FIX_COMPLETED_DATE"
echo "FIX_BRANCH=$FIX_BRANCH"
echo "FIX_ACTOR_NAME=$FIX_ACTOR_NAME"
echo "FIX_ACTOR_EMAIL=$FIX_ACTOR_EMAIL"
echo "FIX_ACTOR=$FIX_ACTOR_NAME <$FIX_ACTOR_EMAIL>"
