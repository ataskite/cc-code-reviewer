#!/bin/bash
# 阶段一：项目识别与准备
# 用途：识别用户提供的路径类型，Git仓库克隆到本地缓存目录
# 缓存策略：相同仓库只克隆一次，后续自动 pull 更新，避免重复克隆

INPUT_PATH="${1:?请输入项目路径或Git URL}"

# 本地缓存目录：统一使用 /tmp 目录，避免污染技能目录
CODE_DIR="/tmp"

# 说明：使用标准 git clone（非浅克隆），确保获取所有远程分支引用

# 识别规则：以http://、https://、git://或git@开头的URL → Git仓库
if [[ "$INPUT_PATH" =~ ^https?:// ]] || [[ "$INPUT_PATH" =~ ^git:// ]] || [[ "$INPUT_PATH" =~ ^git@ ]]; then
  # 从 URL 中提取仓库名作为缓存目录名
  # https://github.com/org/repo.git → org_repo（避免不同 org 同名仓库碰撞）
  # git@github.com:org/repo.git → org_repo
  REPO_NAME=$(echo "$INPUT_PATH" | sed 's/\.git$//' | sed 's|.*://||' | sed 's|.*@||' | sed 's|:|/|' | sed 's:.*/\([^/]*/[^/]*\)$:\1:' | tr '/' '_')
  CACHE_DIR="$CODE_DIR/$REPO_NAME"

  mkdir -p "$CODE_DIR"

  if [ -d "$CACHE_DIR/.git" ]; then
    # 缓存已存在，pull 更新（超时 60 秒）
    echo "检测到Git仓库（缓存命中），正在拉取最新代码..."
    CURRENT_BRANCH=$(git -C "$CACHE_DIR" branch --show-current 2>/dev/null)
    if perl -e 'alarm 60; exec @ARGV' git -C "$CACHE_DIR" pull 2>&1; then
      echo "✅ 已更新到最新: $CACHE_DIR (分支: $CURRENT_BRANCH)"
      PROJECT_DIR="$CACHE_DIR"
      PROJECT_SOURCE="git-cache"
    else
      echo "⚠️ 拉取失败或超时，删除缓存并重新克隆..."
      rm -rf "$CACHE_DIR"
      if perl -e 'alarm 120; exec @ARGV' git clone "$INPUT_PATH" "$CACHE_DIR" 2>&1; then
        echo "✅ 重新克隆成功: $CACHE_DIR"
        PROJECT_DIR="$CACHE_DIR"
        PROJECT_SOURCE="git-cache"
      else
        echo "❌ 克隆失败或超时，请检查Git仓库URL是否正确以及是否有权限访问"
        exit 1
      fi
    fi
  else
    # 缓存不存在，首次克隆（超时 120 秒）
    # 如存在残留目录（非 .git），先清理
    if [ -d "$CACHE_DIR" ]; then
      rm -rf "$CACHE_DIR"
    fi
    echo "检测到Git仓库，正在克隆到缓存目录..."
    if perl -e 'alarm 120; exec @ARGV' git clone "$INPUT_PATH" "$CACHE_DIR" 2>&1; then
      echo "✅ 克隆成功: $CACHE_DIR"
      PROJECT_DIR="$CACHE_DIR"
      PROJECT_SOURCE="git-cache"
    else
      echo "❌ 克隆失败或超时，请检查Git仓库URL是否正确以及是否有权限访问"
      exit 1
    fi
  fi
else
  if [ -d "$INPUT_PATH" ]; then
    echo "检测到本地项目: $INPUT_PATH"
    PROJECT_DIR="$INPUT_PATH"
    PROJECT_SOURCE="local"
  else
    echo "❌ 路径不存在: $INPUT_PATH"
    exit 1
  fi
fi

# 输出结果供主agent解析
echo "PROJECT_DIR=$PROJECT_DIR"
echo "PROJECT_SOURCE=$PROJECT_SOURCE"
