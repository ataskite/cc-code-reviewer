#!/bin/bash
set -euo pipefail

# v1.6.0 契约测试：校验三个审查 agent prompt 的连续七步编号、反思第四步
# 和 fail-open 原则。吸收 OpenCodeReview 的 RE_LOCATION + REVIEW_FILTER 思想。

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

AGENT_FILES=(
  "$ROOT_DIR/agents/cc-code-reviewer.md"
  "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"
  "$ROOT_DIR/agents/cc-code-reviewer-python.md"
)

# 期望的连续七步标题（顺序必须连续）
EXPECTED_STEPS=(
  "### 第一步：执行代码审查"
  "### 第二步：发现归类与证据标注"
  "### 第三步：应用项目 ignore 规则"
  "### 第四步：发现清单自校验（行号回抽 + 证伪过滤）"
  "### 第五步：生成审查报告"
  "### 第六步：持久化报告文件"
  "### 第七步：输出最终汇总"
)

# 反思第四步必须包含的关键思想（fail-open + 两阶段）
REQUIRED_PHRASES=(
  "RE_LOCATION"
  "REVIEW_FILTER"
  "宁可放过，不可错杀"
  "保留原状，绝不删除"
  "只证伪、不证实"
)

for agent_file in "${AGENT_FILES[@]}"; do
  [ -f "$agent_file" ] || { echo "missing agent file: $agent_file" >&2; exit 1; }
  agent_name="$(basename "$agent_file")"

  # 1. 七步连续编号：每个期望标题必须按顺序出现
  prev_line=0
  for step in "${EXPECTED_STEPS[@]}"; do
    line_no="$(grep -nF "$step" "$agent_file" | head -1 | cut -d: -f1 || true)"
    [ -n "$line_no" ] || {
      echo "$agent_name: 缺少步骤标题 '$step'" >&2
      exit 1
    }
    if [ "$line_no" -le "$prev_line" ]; then
      echo "$agent_name: 步骤标题顺序错乱，'$step' (line $line_no) 不应出现在前一步 (line $prev_line) 之前" >&2
      exit 1
    fi
    prev_line="$line_no"
  done

  # 2. 禁止残留旧的"第X步之后"半正式表述
  if grep -qE '第[一二三四五六七八九]步之后' "$agent_file"; then
    echo "$agent_name: 残留旧的'第X步之后'半正式表述（应已重编为连续七步）" >&2
    exit 1
  fi

  # 3. 反思第四步必须包含 fail-open + 两阶段关键思想
  #    提取第四步章节正文（从第四步标题到第五步标题之前）
  step4_start="$(grep -nF "${EXPECTED_STEPS[3]}" "$agent_file" | head -1 | cut -d: -f1)"
  step5_start="$(grep -nF "${EXPECTED_STEPS[4]}" "$agent_file" | head -1 | cut -d: -f1)"
  step4_body="$(sed -n "${step4_start},${step5_start}p" "$agent_file")"
  for phrase in "${REQUIRED_PHRASES[@]}"; do
    if ! printf '%s' "$step4_body" | grep -qF "$phrase"; then
      echo "$agent_name: 反思第四步缺少关键思想 '$phrase'" >&2
      exit 1
    fi
  done

  # 4. 行号回抽必须明确"降级为待确认"而非直接删除（fail-open 体现）
  if ! printf '%s' "$step4_body" | grep -qF "降级"; then
    echo "$agent_name: 行号回抽未命中时必须降级为待确认，不得直接删除" >&2
    exit 1
  fi
done

# report-format.md 的跨文件引用必须同步为第五步
REPORT_FORMAT_FILE="$ROOT_DIR/references/report-format.md"
if ! grep -qF "第五步（生成审查报告）" "$REPORT_FORMAT_FILE"; then
  echo "report-format.md: 跨文件引用未同步为'第五步（生成审查报告）'" >&2
  exit 1
fi
if grep -qE '第[三四]步（生成审查报告）' "$REPORT_FORMAT_FILE"; then
  echo "report-format.md: 残留旧的'第三/四步（生成审查报告）'引用" >&2
  exit 1
fi

echo "PASS: phase14 agent self-verify (7-step renumber + reflection + fail-open)"
