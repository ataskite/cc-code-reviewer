#!/bin/bash
# 阶段二：Git 分支探测与选择
# 用途：检测 Git 仓库的本地分支信息（仅本地分支，取最近5个）

set -e

PROJECT_DIR="${1:?请输入项目路径}"

if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "IS_GIT_REPO=true"
  # 兜底 || true：分离头指针或老版本 git 下 --show-current 可能非 0 退出，避免 set -e 终止检测脚本
  CURRENT_BRANCH=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || true)
  echo "CURRENT_BRANCH=$CURRENT_BRANCH"
  echo ""

  # 列出本地分支，按最近提交时间排序（最多5个）
  LOCAL_TOTAL=$(git -C "$PROJECT_DIR" for-each-ref refs/heads/ --format='%(refname:short)' 2>/dev/null | wc -l | tr -d ' ')
  # 用 git --count=5 在 git 层面限量，不要用 "| head -5"：大仓分支输出超过管道缓冲(64KB)时，
  # head 提前关闭管道会让 git 收到 SIGPIPE(141)，在 set -e 下导致脚本异常退出（Linux 大仓复现）。
  git -C "$PROJECT_DIR" for-each-ref --sort=-committerdate --count=5 \
    --format='BRANCH: %(refname:short) | %(committerdate:format:%Y-%m-%d %H:%M:%S) | %(subject)' refs/heads/
  if [ "$LOCAL_TOTAL" -gt 5 ]; then
    echo "（共 $LOCAL_TOTAL 个本地分支，仅展示最近 5 个）"
  fi
else
  echo "IS_GIT_REPO=false"
fi
