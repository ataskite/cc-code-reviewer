#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/core/decide-batch-mode.sh"

assert_line() {
  local output="$1"
  local expected="$2"
  if ! grep -Fxq "$expected" <<<"$output"; then
    echo "缺少预期输出: $expected" >&2
    echo "$output" >&2
    exit 1
  fi
}

# 回归：几千行的 Maven 多模块全量审查不得展示步骤 4B，也不得进入分批。
output="$(bash "$SCRIPT" maven-multi 存量审查 40 5000 single-agent)"
assert_line "$output" "ESTIMATED_TOKENS=35000"
assert_line "$output" "STEP_4B_REQUIRED=false"
assert_line "$output" "STOCK_REVIEW_STRATEGY=single-agent"
assert_line "$output" "BATCH_MODE=false"
assert_line "$output" "MAVEN_LARGE_REPO_MODE=false"

# 即使带入旧的 module-sequential 状态，小仓库也必须归一化回单 agent。
output="$(bash "$SCRIPT" maven-multi 存量审查 40 5000 module-sequential)"
assert_line "$output" "STEP_4B_REQUIRED=false"
assert_line "$output" "STOCK_REVIEW_STRATEGY=single-agent"
assert_line "$output" "BATCH_MODE=false"

# 当前范围达到 120k 行门槛后才展示 4B；选择策略后进入 Maven 大仓模式。
output="$(bash "$SCRIPT" maven-multi 存量审查 100 120000 single-agent)"
assert_line "$output" "MAVEN_LARGE_REPO_REQUIRED=true"
assert_line "$output" "STEP_4B_REQUIRED=true"
assert_line "$output" "BATCH_MODE=false"

output="$(bash "$SCRIPT" maven-multi 存量审查 100 120000 ai-planned)"
assert_line "$output" "STEP_4B_REQUIRED=true"
assert_line "$output" "STOCK_REVIEW_STRATEGY=ai-planned"
assert_line "$output" "BATCH_MODE=true"
assert_line "$output" "MAVEN_LARGE_REPO_MODE=true"

# 非 Maven 多模块项目仍按 500k token 门槛自动进入文件级分批。
output="$(bash "$SCRIPT" gradle-single 存量审查 500 100000 single-agent)"
assert_line "$output" "ESTIMATED_TOKENS=550000"
assert_line "$output" "SIZE_BATCH_REQUIRED=true"
assert_line "$output" "STEP_4B_REQUIRED=false"
assert_line "$output" "BATCH_MODE=true"

# 增量审查无论规模多大都不得分批。
output="$(bash "$SCRIPT" maven-multi 增量审查 2000 500000 ai-planned)"
assert_line "$output" "STEP_4B_REQUIRED=false"
assert_line "$output" "BATCH_MODE=false"
assert_line "$output" "MAVEN_LARGE_REPO_MODE=false"

if bash "$SCRIPT" maven-multi 存量审查 not-a-number 5000 single-agent >/dev/null 2>&1; then
  echo "非法文件数必须失败" >&2
  exit 1
fi

echo "decide-batch-mode tests passed"
