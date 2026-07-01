#!/bin/bash
# 阶段五：代码审查 - 增量审查预处理
# 用途：获取提交记录、变更文件列表和变更统计

set -e

PROJECT_DIR="${1:?请输入项目路径}"
COMMIT_COUNT="${2:?请输入提交次数}"

# 防止 HEAD~N 越界：获取实际提交数
TOTAL_COMMITS=$(git -C "$PROJECT_DIR" rev-list --count HEAD 2>/dev/null || echo "0")
if [ "$TOTAL_COMMITS" -lt "$COMMIT_COUNT" ]; then
  echo "⚠️ 项目仅有 $TOTAL_COMMITS 次提交，将使用实际数量"
  COMMIT_COUNT="$TOTAL_COMMITS"
fi

echo "# === 提交记录 ==="
if [ "$COMMIT_COUNT" -eq 0 ]; then
  echo "（无提交记录）"
else
  git -C "$PROJECT_DIR" log --oneline -"$COMMIT_COUNT"
fi

echo ""
echo "# === 变更文件列表 ==="
if [ "$COMMIT_COUNT" -eq 0 ]; then
  echo "（无提交记录）"
elif [ "$COMMIT_COUNT" -ge "$TOTAL_COMMITS" ]; then
  git -C "$PROJECT_DIR" diff --name-only 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD
elif [ "$TOTAL_COMMITS" -eq 1 ]; then
  git -C "$PROJECT_DIR" show --format="" --name-only HEAD
else
  git -C "$PROJECT_DIR" diff --name-only HEAD~"$COMMIT_COUNT"..HEAD
fi

echo ""
echo "# === 变更统计 ==="
if [ "$COMMIT_COUNT" -eq 0 ]; then
  echo "（无变更）"
elif [ "$COMMIT_COUNT" -ge "$TOTAL_COMMITS" ]; then
  git -C "$PROJECT_DIR" diff --stat 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD
elif [ "$TOTAL_COMMITS" -eq 1 ]; then
  git -C "$PROJECT_DIR" show --stat --format="" HEAD
else
  git -C "$PROJECT_DIR" diff --stat HEAD~"$COMMIT_COUNT"..HEAD
fi
