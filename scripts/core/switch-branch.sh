#!/bin/bash
# 阶段二：Git 分支探测与选择 - 步骤C
# 用途：切换到用户选择的分支（支持本地和远程分支）

set -e

PROJECT_DIR="${1:?请输入项目路径}"
TARGET_BRANCH="${2:?请输入目标分支}"
CURRENT_BRANCH="${3:?请输入当前分支}"
PROJECT_SOURCE="${4:-unknown}"

# 如果目标分支就是当前分支，无需切换
if [ "$TARGET_BRANCH" == "$CURRENT_BRANCH" ]; then
  echo "✅ 已在目标分支: $CURRENT_BRANCH"
  exit 0
fi

# 函数：检查本地分支是否存在
local_branch_exists() {
  git -C "$PROJECT_DIR" show-ref --verify --quiet "refs/heads/$1" 2>/dev/null
}

# 函数：检查远程分支是否存在
remote_branch_exists() {
  git -C "$PROJECT_DIR" show-ref --verify --quiet "refs/remotes/origin/$1" 2>/dev/null
}

# 去掉 origin/ 前缀，获取短分支名
SHORT_BRANCH=$(echo "$TARGET_BRANCH" | sed 's|^origin/||')

echo "正在切换到分支: $SHORT_BRANCH"

# 本地项目目录可能承载用户的在途改动，此时不主动切分支。
if [ "$PROJECT_SOURCE" = "local" ]; then
  DIRTY_STATUS=$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null || true)
  if [ -n "$DIRTY_STATUS" ]; then
    echo "⚠️ 检测到本地项目目录存在未提交改动，为避免影响当前工作区，将继续使用当前分支 $CURRENT_BRANCH 审查"
    exit 1
  fi
fi

# 判断分支类型并执行切换
if local_branch_exists "$SHORT_BRANCH"; then
  # 本地分支存在，直接切换
  if git -C "$PROJECT_DIR" checkout "$SHORT_BRANCH" 2>&1; then
    echo "✅ 已切换到本地分支: $SHORT_BRANCH"
  else
    echo "⚠️ 分支切换失败，将使用当前分支 $CURRENT_BRANCH 继续审查"
    exit 1
  fi
elif remote_branch_exists "$SHORT_BRANCH"; then
  # 远程分支存在，先 fetch 再切换
  echo "检测到远程分支，正在拉取最新代码..."
  if git -C "$PROJECT_DIR" fetch origin "$SHORT_BRANCH" 2>&1; then
    if git -C "$PROJECT_DIR" checkout "$SHORT_BRANCH" 2>&1; then
      echo "✅ 已切换到远程分支: $SHORT_BRANCH"
    else
      echo "⚠️ 分支切换失败，将使用当前分支 $CURRENT_BRANCH 继续审查"
      exit 1
    fi
  else
    echo "⚠️ 远程分支拉取失败，将使用当前分支 $CURRENT_BRANCH 继续审查"
    exit 1
  fi
else
  # 分支不存在
  echo "⚠️ 分支 '$SHORT_BRANCH' 不存在（本地或远程均未找到），将使用当前分支 $CURRENT_BRANCH 继续审查"
  exit 1
fi
