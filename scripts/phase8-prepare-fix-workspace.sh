#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:-}"
MODE="${2:-}"
REQUESTED_BRANCH="${3:-}"

if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
  echo "项目路径不存在: $PROJECT_DIR" >&2
  exit 1
fi

if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "当前项目不是 Git 仓库，fix 阶段需要 Git 工作区" >&2
  exit 1
fi

CURRENT_BRANCH="$(git -C "$PROJECT_DIR" branch --show-current)"
if [ -z "$CURRENT_BRANCH" ]; then
  CURRENT_BRANCH="detached-head"
fi

is_dirty() {
  [ -n "$(git -C "$PROJECT_DIR" status --porcelain)" ]
}

validate_branch() {
  local branch="$1"

  if [ -z "$branch" ]; then
    echo "修复分支名不能为空" >&2
    exit 1
  fi

  if ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
    echo "非法修复分支名: $branch" >&2
    exit 1
  fi
}

ensure_worktrees_ignored() {
  local exclude_file

  exclude_file="$(git -C "$PROJECT_DIR" rev-parse --git-path info/exclude)"
  case "$exclude_file" in
    /*) ;;
    *) exclude_file="$PROJECT_DIR/$exclude_file" ;;
  esac
  mkdir -p "$(dirname "$exclude_file")"
  touch "$exclude_file"

  if ! grep -qxF ".worktrees/" "$exclude_file"; then
    printf '\n.worktrees/\n' >> "$exclude_file"
  fi
}

case "$MODE" in
  current)
    echo "FIX_WORKSPACE_MODE=current"
    echo "FIX_WORKSPACE_PATH=$PROJECT_DIR"
    echo "FIX_BRANCH=$CURRENT_BRANCH"
    ;;
  branch)
    validate_branch "$REQUESTED_BRANCH"
    if is_dirty; then
      echo "存在未提交改动，不能在当前仓库直接创建修复分支" >&2
      exit 1
    fi

    if git -C "$PROJECT_DIR" show-ref --verify --quiet "refs/heads/$REQUESTED_BRANCH"; then
      git -C "$PROJECT_DIR" switch "$REQUESTED_BRANCH" >/dev/null 2>&1
    else
      git -C "$PROJECT_DIR" switch -c "$REQUESTED_BRANCH" >/dev/null 2>&1
    fi

    echo "FIX_WORKSPACE_MODE=branch"
    echo "FIX_WORKSPACE_PATH=$PROJECT_DIR"
    echo "FIX_BRANCH=$REQUESTED_BRANCH"
    ;;
  worktree)
    validate_branch "$REQUESTED_BRANCH"
    PROJECT_NAME="$(basename "$PROJECT_DIR")"
    WORKTREE_ROOT="$PROJECT_DIR/.worktrees"
    WORKTREE_PATH="$WORKTREE_ROOT/$REQUESTED_BRANCH"
    ensure_worktrees_ignored

    if [ -e "$WORKTREE_PATH" ]; then
      echo "修复 worktree 已存在: $WORKTREE_PATH" >&2
      exit 1
    fi

    if is_dirty; then
      echo "存在未提交改动，不能从脏工作区创建修复 worktree" >&2
      exit 1
    fi

    mkdir -p "$WORKTREE_ROOT"

    if git -C "$PROJECT_DIR" show-ref --verify --quiet "refs/heads/$REQUESTED_BRANCH"; then
      git -C "$PROJECT_DIR" worktree add "$WORKTREE_PATH" "$REQUESTED_BRANCH" >/dev/null 2>&1
    else
      git -C "$PROJECT_DIR" worktree add "$WORKTREE_PATH" -b "$REQUESTED_BRANCH" >/dev/null 2>&1
    fi

    echo "FIX_WORKSPACE_MODE=worktree"
    echo "FIX_WORKSPACE_PATH=$WORKTREE_PATH"
    echo "FIX_BRANCH=$REQUESTED_BRANCH"
    echo "FIX_WORKTREE_PROJECT=$PROJECT_NAME"
    ;;
  *)
    echo "未知工作区策略: $MODE" >&2
    exit 1
    ;;
esac
