#!/bin/bash
# 代码审查预估耗时（语言中立，单 agent 与批次模式的单一真相源）
#
# 既有且已被测试覆盖的时间模型：
#   review_cost  = REVIEW_LINE_COUNT + REVIEW_FILE_COUNT × 25   （缺失 planned_review_cost 时的 fallback）
#   mode_minutes = fast 4 / standard 8 / deep 15 / security 10
#   estimated_minutes = ceil(review_cost × mode_minutes / (52000 × CONTEXT_SCALE))，下限 1
#
# 调用方式：
#   1) 作为 CLI：bash estimate-review-minutes.sh <REVIEW_MODE> <REVIEW_LINE_COUNT> <REVIEW_FILE_COUNT> [CONTEXT_SCALE]
#      输出两行：
#        ESTIMATED_MINUTES=<int>
#        ESTIMATED_RANGE=<min>-<max> 分钟        （区间 = [ceil(分钟×0.8), ceil(分钟×1.3)]，下限 1）
#   2) 作为函数库被 source：提供 review_cost_of / target_review_minutes / ceil_div / estimate_review_minutes
#      core/show-batch-status.sh source 本文件复用这些函数，批次/单 agent 口径保持一致。
#
# 说明：
#   - 此公式与批次模式的 batch_estimate_minutes() 同源，单 agent 把「整个审查范围」视作一个批次。
#   - 输入 REVIEW_LINE_COUNT / REVIEW_FILE_COUNT 语言无关：Java 来自 languages/java/project-scan.sh，前端来自 scan-project.sh PROFILE。
#   - CONTEXT_SCALE 由 core/detect-model-context.sh 探测（1M 窗口 → 5，200k → 1），大窗口下分钟数按比例下降。
set -euo pipefail

# ── 公共函数（被 show-batch-status.sh source 复用，禁止改变签名/语义） ──

# ceil(a/b)，分母 <=0 视作 1
ceil_div() {
  local numerator="${1:-0}"
  local denominator="${2:-1}"
  if [ "$denominator" -le 0 ]; then
    denominator=1
  fi
  echo $(((numerator + denominator - 1) / denominator))
}

# 各模式的目标批次耗时（分钟）。唯一的耗时系数来源。
target_review_minutes() {
  case "${1:-standard}" in
    fast) echo 4 ;;
    deep) echo 15 ;;
    security) echo 10 ;;
    *) echo 8 ;;
  esac
}

# 基准目标批次成本（200k 窗口）。CONTEXT_SCALE=5 时批次容量放大 5 倍，单批耗时随之按比例下降。
TARGET_REVIEW_COST_BASE=52000

# review_cost = loc + files × 25
review_cost_of() {
  local loc="${1:-0}"
  local files="${2:-0}"
  loc="${loc:-0}"; files="${files:-0}"
  echo $((loc + files * 25))
}

# estimate_review_minutes <review_cost> <review_mode> [CONTEXT_SCALE]
# 等价于批次模式 batch_estimate_minutes（cost 已知分支），下限 1 分钟。
estimate_review_minutes() {
  local review_cost="${1:-0}"
  local review_mode="${2:-standard}"
  local context_scale="${3:-1}"
  review_cost="${review_cost:-0}"; context_scale="${context_scale:-1}"
  [ "$context_scale" -lt 1 ] 2>/dev/null && context_scale=1
  local target_cost=$((TARGET_REVIEW_COST_BASE * context_scale))
  local target_minutes
  target_minutes="$(target_review_minutes "$review_mode")"
  local minutes
  minutes="$(ceil_div $((review_cost * target_minutes)) "$target_cost")"
  if [ "$minutes" -lt 1 ]; then
    minutes=1
  fi
  echo "$minutes"
}

# ── 仅在作为 CLI 直接执行时生效（被 source 时不触发） ──
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  if [ "$#" -lt 3 ]; then
    echo "用法: bash estimate-review-minutes.sh <REVIEW_MODE> <REVIEW_LINE_COUNT> <REVIEW_FILE_COUNT> [CONTEXT_SCALE]" >&2
    echo "  REVIEW_MODE: fast | standard | deep | security" >&2
    exit 1
  fi

  CLI_MODE="${1:?请输入审查模式}"
  CLI_LOC="${2:?请输入代码行数}"
  CLI_FILES="${3:?请输入文件数}"
  CLI_SCALE="${4:-1}"

  # 容错：非整数归零，避免 set -e 下直接退出
  [[ "$CLI_LOC" =~ ^[0-9]+$ ]] || CLI_LOC=0
  [[ "$CLI_FILES" =~ ^[0-9]+$ ]] || CLI_FILES=0
  [[ "$CLI_SCALE" =~ ^[0-9]+$ ]] || CLI_SCALE=1

  CLI_COST="$(review_cost_of "$CLI_LOC" "$CLI_FILES")"
  CLI_MINUTES="$(estimate_review_minutes "$CLI_COST" "$CLI_MODE" "$CLI_SCALE")"

  # 区间 = [ceil(分钟×0.8), ceil(分钟×1.3)]，给真实波动留余量，下限 1
  CLI_MIN_LO="$(ceil_div $((CLI_MINUTES * 8)) 10)"
  CLI_MIN_HI="$(ceil_div $((CLI_MINUTES * 13)) 10)"
  [ "$CLI_MIN_LO" -lt 1 ] && CLI_MIN_LO=1

  echo "ESTIMATED_MINUTES=$CLI_MINUTES"
  echo "ESTIMATED_RANGE=${CLI_MIN_LO}-${CLI_MIN_HI} 分钟"
fi
