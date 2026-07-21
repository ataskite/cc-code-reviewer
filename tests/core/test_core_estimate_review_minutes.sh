#!/bin/bash
# 测试：scripts/core/estimate-review-minutes.sh
# 覆盖场景：
#   1. CLI 输出契约（ESTIMATED_MINUTES / ESTIMATED_RANGE 两行）
#   2. 核心用例点估计：
#      - 前端 deep 209 文件 / 15,882 行（用户原始误报项目）→ 2-3 分钟区间
#      - Java fast 小项目 42 文件 / 3,850 行 → 下限 1 分钟
#      - Java deep 186 文件 / 28,500 行 → 2-3 分钟区间
#   3. 旧 scale 参数不再改变固定 1M 估算
#   4. 各模式系数：fast 4 / standard 8 / deep 15 / security 10
#   5. source 复用：被 phase13 source 后 target_review_minutes / ceil_div / review_cost_of 可用
#   6. 错误用法（参数不足）→ 报错退出
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/core/estimate-review-minutes.sh"

# 取点估计
minutes_of() {
  bash "$SCRIPT" "$1" "$2" "$3" "${4:-1}" | sed -n 's/^ESTIMATED_MINUTES=//p'
}

# 取区间
range_of() {
  bash "$SCRIPT" "$1" "$2" "$3" "${4:-1}" | sed -n 's/^ESTIMATED_RANGE=//p'
}

# ── 1. CLI 输出契约 ──
OUT="$(bash "$SCRIPT" deep 15882 209)"
echo "$OUT" | grep -qE '^ESTIMATED_MINUTES=[0-9]+$'
echo "$OUT" | grep -qE '^ESTIMATED_RANGE=[0-9]+-[0-9]+ 分钟$'

# ── 2. 核心用例点估计 ──
# 用户原始误报项目：209 文件 / 15,882 行 / deep → cost=21107 → 21107×15/260000=1.22 → 2 分钟
# （修正前固定表误报为 30-50 分钟，虚高约 5 倍）
FE_MIN="$(minutes_of deep 15882 209)"
[ "$FE_MIN" = "2" ] || { echo "FAIL: 前端 deep 应为 2 分钟，实际 $FE_MIN" >&2; exit 1; }
FE_RANGE="$(range_of deep 15882 209)"
[ "$FE_RANGE" = "2-3 分钟" ] || { echo "FAIL: 前端 deep 区间应为 2-3 分钟，实际 $FE_RANGE" >&2; exit 1; }

# Java fast 小项目：42 文件 / 3,850 行 → cost=4900 → 4900×4/52000=0.377 → 下限 1 分钟
JA_MIN="$(minutes_of fast 3850 42)"
[ "$JA_MIN" = "1" ] || { echo "FAIL: Java fast 应为 1 分钟，实际 $JA_MIN" >&2; exit 1; }

# Java deep 186 文件 / 28,500 行 → cost=33150 → 33150×15/260000=1.92 → 2 分钟
JA_DEEP_MIN="$(minutes_of deep 28500 186)"
[ "$JA_DEEP_MIN" = "2" ] || { echo "FAIL: Java deep 应为 2 分钟，实际 $JA_DEEP_MIN" >&2; exit 1; }
JA_DEEP_RANGE="$(range_of deep 28500 186)"
[ "$JA_DEEP_RANGE" = "2-3 分钟" ] || { echo "FAIL: Java deep 区间应为 2-3 分钟，实际 $JA_DEEP_RANGE" >&2; exit 1; }

# ── 3. 旧 scale 参数不再改变固定 1M 估算 ──
SCALE1_MIN="$(minutes_of deep 15882 209 1)"
SCALE5_MIN="$(minutes_of deep 15882 209 5)"
[ "$SCALE1_MIN" = "2" ] || { echo "FAIL: 旧 scale=1 不应降低固定 1M 预算" >&2; exit 1; }
[ "$SCALE5_MIN" = "2" ] || { echo "FAIL: 固定 1M 估算应为 2 分钟，实际 $SCALE5_MIN" >&2; exit 1; }

# ── 4. 各模式系数（同一规模下 fast < security < standard < deep） ──
M_FAST="$(minutes_of fast 260000 0)"
M_SEC="$(minutes_of security 260000 0)"
M_STD="$(minutes_of standard 260000 0)"
M_DEEP="$(minutes_of deep 260000 0)"
# cost=260000（固定 1M 满批次）时：fast=4, security=10, standard=8, deep=15
[ "$M_FAST" = "4" ] || { echo "FAIL: 满批 fast 应为 4 分钟" >&2; exit 1; }
[ "$M_SEC" = "10" ] || { echo "FAIL: 满批 security 应为 10 分钟" >&2; exit 1; }
[ "$M_STD" = "8" ] || { echo "FAIL: 满批 standard 应为 8 分钟" >&2; exit 1; }
[ "$M_DEEP" = "15" ] || { echo "FAIL: 满批 deep 应为 15 分钟" >&2; exit 1; }

# ── 5. source 复用：phase13 source 后函数可用，且与直接调用一致 ──
# 用子 shell source 后调用，验证函数被导出
SOURCE_CHECK="$(
  # shellcheck source=/dev/null
  . "$SCRIPT"
  # source 模式下不应触发 CLI 块
  COST="$(review_cost_of 28500 186)"
  echo "COST=$COST"
  echo "MODE_MIN=$(target_review_minutes deep)"
  echo "CEIL=$(ceil_div 956 52000)"
  echo "EST=$(estimate_review_minutes "$COST" deep)"
)"
echo "$SOURCE_CHECK" | grep -q '^COST=33150$'
echo "$SOURCE_CHECK" | grep -q '^MODE_MIN=15$'
echo "$SOURCE_CHECK" | grep -q '^CEIL=1$'
echo "$SOURCE_CHECK" | grep -q '^EST=2$'

# ── 6. 错误用法：参数不足 → 报错退出 ──
if bash "$SCRIPT" deep 2>/dev/null; then
  echo "FAIL: 参数不足应报错退出" >&2; exit 1
fi

echo "PASS: core estimate-review-minutes"
