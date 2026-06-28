#!/bin/bash
# 阶段二：Git 分支探测与选择
# 用途：检测 Git 仓库的本地分支信息（仅本地分支，取最近5个）

set -e

PROJECT_DIR="${1:?请输入项目路径}"

if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "IS_GIT_REPO=true"
  CURRENT_BRANCH=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null)
  echo "CURRENT_BRANCH=$CURRENT_BRANCH"
  echo ""

  # 列出本地分支，按最近提交时间排序（最多5个）
  LOCAL_TOTAL=$(git -C "$PROJECT_DIR" for-each-ref refs/heads/ --format='%(refname:short)' 2>/dev/null | wc -l | tr -d ' ')
  git -C "$PROJECT_DIR" for-each-ref --sort=-committerdate \
    --format='BRANCH: %(refname:short) | %(committerdate:format:%Y-%m-%d %H:%M:%S) | %(subject)' refs/heads/ | head -5
  if [ "$LOCAL_TOTAL" -gt 5 ]; then
    echo "（共 $LOCAL_TOTAL 个本地分支，仅展示最近 5 个）"
  fi
else
  echo "IS_GIT_REPO=false"
fi
