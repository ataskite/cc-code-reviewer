#!/bin/bash
# 基于“当前已确认审查范围”的规模，确定是否需要分批以及是否展示 Maven 步骤 4B。
#
# 用法：
#   bash decide-batch-mode.sh \
#     <PROJECT_TYPE> <REVIEW_TYPE> <REVIEW_FILE_COUNT> <REVIEW_LINE_COUNT> \
#     [STOCK_REVIEW_STRATEGY]
#
# STOCK_REVIEW_STRATEGY 默认为 single-agent。Maven 多模块只有当前范围达到
# 大仓门槛时才允许 module-sequential / ai-planned 生效，避免旧状态或错误交互把
# 小仓库强制送入分批路径。
set -euo pipefail

PROJECT_TYPE="${1:?请输入项目类型}"
REVIEW_TYPE="${2:?请输入审查类型}"
REVIEW_FILE_COUNT="${3:?请输入审查文件数}"
REVIEW_LINE_COUNT="${4:?请输入审查代码行数}"
REQUESTED_STOCK_REVIEW_STRATEGY="${5:-single-agent}"

if ! [[ "$REVIEW_FILE_COUNT" =~ ^[0-9]+$ ]]; then
  echo "INVALID_REVIEW_FILE_COUNT=$REVIEW_FILE_COUNT" >&2
  exit 1
fi
if ! [[ "$REVIEW_LINE_COUNT" =~ ^[0-9]+$ ]]; then
  echo "INVALID_REVIEW_LINE_COUNT=$REVIEW_LINE_COUNT" >&2
  exit 1
fi

case "$REQUESTED_STOCK_REVIEW_STRATEGY" in
  single-agent|module-sequential|ai-planned) ;;
  *)
    echo "INVALID_STOCK_REVIEW_STRATEGY=$REQUESTED_STOCK_REVIEW_STRATEGY" >&2
    exit 1
    ;;
esac

ESTIMATED_TOKENS=$((REVIEW_FILE_COUNT * 500 + REVIEW_LINE_COUNT * 3))
SIZE_BATCH_REQUIRED=false
MAVEN_LARGE_REPO_REQUIRED=false
STEP_4B_REQUIRED=false
BATCH_MODE=false
MAVEN_LARGE_REPO_MODE=false
STOCK_REVIEW_STRATEGY="$REQUESTED_STOCK_REVIEW_STRATEGY"

if [ "$REVIEW_TYPE" = "存量审查" ] && [ "$ESTIMATED_TOKENS" -gt 500000 ]; then
  SIZE_BATCH_REQUIRED=true
fi

if [ "$PROJECT_TYPE" = "maven-multi" ] && [ "$REVIEW_TYPE" = "存量审查" ]; then
  if [ "$SIZE_BATCH_REQUIRED" = "true" ] || [ "$REVIEW_LINE_COUNT" -ge 120000 ]; then
    MAVEN_LARGE_REPO_REQUIRED=true
    STEP_4B_REQUIRED=true
  else
    # 小型 Maven 多模块仓库固定走单 agent。即使上一步残留了分批策略，
    # 也在这里归一化，防止状态串线。
    STOCK_REVIEW_STRATEGY=single-agent
  fi
fi

if [ "$REVIEW_TYPE" = "存量审查" ]; then
  if [ "$PROJECT_TYPE" = "maven-multi" ]; then
    if [ "$MAVEN_LARGE_REPO_REQUIRED" = "true" ] && \
       { [ "$STOCK_REVIEW_STRATEGY" = "module-sequential" ] || [ "$STOCK_REVIEW_STRATEGY" = "ai-planned" ]; }; then
      BATCH_MODE=true
      MAVEN_LARGE_REPO_MODE=true
    fi
  elif [ "$SIZE_BATCH_REQUIRED" = "true" ]; then
    BATCH_MODE=true
  fi
fi

echo "ESTIMATED_TOKENS=$ESTIMATED_TOKENS"
echo "SIZE_BATCH_REQUIRED=$SIZE_BATCH_REQUIRED"
echo "MAVEN_LARGE_REPO_REQUIRED=$MAVEN_LARGE_REPO_REQUIRED"
echo "STEP_4B_REQUIRED=$STEP_4B_REQUIRED"
echo "STOCK_REVIEW_STRATEGY=$STOCK_REVIEW_STRATEGY"
echo "BATCH_MODE=$BATCH_MODE"
echo "MAVEN_LARGE_REPO_MODE=$MAVEN_LARGE_REPO_MODE"
