#!/bin/bash
# 阶段五：代码审查 - 增量审查提交预览
# 用途：展示最近 10 次提交，帮助用户选择增量审查范围

set -e

PROJECT_DIR="${1:?请输入项目路径}"
PREVIEW_COUNT=10

TOTAL_COMMITS=$(git -C "$PROJECT_DIR" rev-list --count HEAD 2>/dev/null || echo "0")

echo "# === 最近提交预览 ==="
if [ "$TOTAL_COMMITS" -eq 0 ]; then
  echo "（无提交记录）"
else
  git -C "$PROJECT_DIR" log --pretty=format:'%h %s' -"$PREVIEW_COUNT" | awk '{print NR ". " $0}'
fi
