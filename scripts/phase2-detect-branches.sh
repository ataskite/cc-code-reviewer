#!/bin/bash
# 阶段二：Git 分支探测与选择 - 步骤A
# 用途：检测 Git 仓库的分支信息

set -e

PROJECT_DIR="${1:?请输入项目路径}"

if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "IS_GIT_REPO=true"
  CURRENT_BRANCH=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null)
  echo "CURRENT_BRANCH=$CURRENT_BRANCH"
  echo ""

  # 主动获取远程分支信息（仅更新引用，不下载内容）
  # 使用 --no-tags 避免下载标签
  # 设置超时时间为10秒，避免长时间等待
  # 使用 perl alarm 兼容 macOS（macOS 默认无 timeout 命令）
  perl -e 'alarm 10; exec @ARGV' git -C "$PROJECT_DIR" fetch --no-tags --quiet 2>/dev/null || true

  # 列出本地分支，按最近提交时间排序（最多10个）
  echo "=== 本地分支 ==="
  LOCAL_TOTAL=$(git -C "$PROJECT_DIR" for-each-ref refs/heads/ --format='%(refname:short)' 2>/dev/null | wc -l | tr -d ' ')
  git -C "$PROJECT_DIR" for-each-ref --sort=-committerdate \
    --format='BRANCH: %(refname:short) | %(committerdate:format:%Y-%m-%d %H:%M:%S) | %(subject)' refs/heads/ | head -10
  if [ "$LOCAL_TOTAL" -gt 10 ]; then
    echo "（共 $LOCAL_TOTAL 个本地分支，仅展示最近 10 个）"
  fi

  # 列出远程分支（排除 origin/HEAD 和 origin 本身）
  echo ""
  echo "=== 远程分支 ==="
  REMOTE_TOTAL=$(git -C "$PROJECT_DIR" for-each-ref refs/remotes/ --format='%(refname:short)' 2>/dev/null | grep -v '/HEAD$' | wc -l | tr -d ' ')
  git -C "$PROJECT_DIR" for-each-ref --sort=-committerdate \
    --format='%(refname:short)' refs/remotes/ | grep -v '/HEAD$' | while read -r ref; do
    short_name=$(echo "$ref" | sed 's|^origin/||')
    date=$(git -C "$PROJECT_DIR" log -1 --format='%cd' --date='format:%Y-%m-%d %H:%M:%S' "$ref" 2>/dev/null)
    subject=$(git -C "$PROJECT_DIR" log -1 --format='%s' "$ref" 2>/dev/null | cut -c1-30)
    echo "BRANCH_REMOTE: $ref | $date | $subject"
  done | head -10
  if [ "$REMOTE_TOTAL" -gt 10 ]; then
    echo "（共 $REMOTE_TOTAL 个远程分支，仅展示最近 10 个）"
  fi
else
  echo "IS_GIT_REPO=false"
fi
