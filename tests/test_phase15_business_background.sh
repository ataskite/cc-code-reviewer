#!/bin/bash
set -euo pipefail

# phase15 契约测试：业务背景注入（agent 侧）。吸收 OpenCodeReview --background 思想。
# 三个语言审查 agent 必须同构地声明：
#   1. 审查任务参数表含「业务背景（可选）」行（REVIEW_BACKGROUND 或 未提供，≤8000 字符）
#   2. 参数注入章节内、审查模式定义之前存在「业务背景使用规则」小节，覆盖五条规则关键词
#   3. 增量提交记录处声明 commit message 默认源（由主 Skill 注入，无需自行拼接）
#   4. 阶段 C 含「不扩大也不缩小审查范围」的背景定向警觉提示
#   5. 既有契约（语义分组清单行、filetype_checklists 段）未被误删

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

AGENT_FILES=(
  "$ROOT_DIR/agents/cc-code-reviewer.md"
  "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"
  "$ROOT_DIR/agents/cc-code-reviewer-python.md"
)

# 1. 参数表行关键内容
PARAM_ROW_PHRASES=(
  "业务背景（可选）"
  "REVIEW_BACKGROUND 或 未提供"
  "≤8000 字符"
)

# 2. 「业务背景使用规则」小节必须覆盖的规则关键词（五条规则）
RULES_PHRASES=(
  "不得替代代码证据"
  "以代码为准"
  "不得虚构"
  "commit message"
  "线索而非事实"
  "不影响 ignore 规则"
)

# 3. 增量 commit message 默认源说明（整句）
DEFAULT_SOURCE_SENTENCE="若未单独提供业务背景，上述提交记录即视为业务背景的默认来源（由主 Skill 注入，无需自行拼接）。"

# 5. 既有契约防误删守卫
LEGACY_GUARD_PHRASES=(
  "语义分组清单"
  "filetype_checklists"
)

checks=0

for agent_file in "${AGENT_FILES[@]}"; do
  [ -f "$agent_file" ] || { echo "missing agent file: $agent_file" >&2; exit 1; }
  agent_name="$(basename "$agent_file")"

  param_header_line="$(grep -nF '## 审查任务参数（外部注入，请直接使用，无需再次确认）' "$agent_file" | head -1 | cut -d: -f1 || true)"
  [ -n "$param_header_line" ] || {
    echo "$agent_name: 缺少「审查任务参数」表头" >&2
    exit 1
  }
  mode_def_line="$(grep -nF '## 审查模式定义' "$agent_file" | head -1 | cut -d: -f1 || true)"
  [ -n "$mode_def_line" ] || {
    echo "$agent_name: 缺少「## 审查模式定义」章节" >&2
    exit 1
  }

  # 1. 参数表行：三个关键内容都必须落在参数表头与审查模式定义之间
  for phrase in "${PARAM_ROW_PHRASES[@]}"; do
    phrase_line="$(grep -nF "$phrase" "$agent_file" | head -1 | cut -d: -f1 || true)"
    [ -n "$phrase_line" ] || {
      echo "$agent_name: 参数表缺少业务背景行关键内容 '$phrase'" >&2
      exit 1
    }
    if [ "$phrase_line" -le "$param_header_line" ] || [ "$phrase_line" -ge "$mode_def_line" ]; then
      echo "$agent_name: 业务背景参数行关键内容 '$phrase' 必须位于参数表内（表头 line $param_header_line 与 审查模式定义 line $mode_def_line 之间，实际 line $phrase_line）" >&2
      exit 1
    fi
    checks=$((checks + 1))
  done

  # 2. 「业务背景使用规则」小节：标题存在、位于参数注入区内（审查模式定义之前）、五条规则齐全
  rules_start="$(grep -nF '### 业务背景使用规则' "$agent_file" | head -1 | cut -d: -f1 || true)"
  [ -n "$rules_start" ] || {
    echo "$agent_name: 缺少「### 业务背景使用规则」小节" >&2
    exit 1
  }
  checks=$((checks + 1))
  if [ "$rules_start" -le "$param_header_line" ] || [ "$rules_start" -ge "$mode_def_line" ]; then
    echo "$agent_name: 「业务背景使用规则」小节必须位于参数表之后、审查模式定义之前（实际 line $rules_start）" >&2
    exit 1
  fi
  rules_end="$(awk -v s="$rules_start" 'NR > s && /^## / {print NR; exit}' "$agent_file")"
  [ -n "$rules_end" ] || rules_end='$'
  rules_body="$(sed -n "${rules_start},${rules_end}p" "$agent_file")"
  for phrase in "${RULES_PHRASES[@]}"; do
    if ! printf '%s' "$rules_body" | grep -qF "$phrase"; then
      echo "$agent_name: 「业务背景使用规则」缺少规则关键词 '$phrase'" >&2
      exit 1
    fi
    checks=$((checks + 1))
  done

  # 3. 增量默认源说明整句必须出现在提交记录注入说明附近
  if ! grep -qF "$DEFAULT_SOURCE_SENTENCE" "$agent_file"; then
    echo "$agent_name: 增量提交记录处缺少 commit message 默认业务背景来源说明" >&2
    exit 1
  fi
  checks=$((checks + 1))

  # 4. 阶段 C（Python 为 Phase C）内必须含背景定向警觉提示「不扩大也不缩小审查范围」
  phase_c_start="$(grep -nE '^(#### 阶段 C|\*\*Phase C)' "$agent_file" | head -1 | cut -d: -f1 || true)"
  [ -n "$phase_c_start" ] || {
    echo "$agent_name: 缺少阶段 C/Phase C 标题，无法定位背景提示区间" >&2
    exit 1
  }
  phase_d_start="$(grep -nE '^(#### 阶段 D|\*\*Phase D)' "$agent_file" | head -1 | cut -d: -f1 || true)"
  [ -n "$phase_d_start" ] || {
    echo "$agent_name: 缺少阶段 D/Phase D 标题，无法定位背景提示区间" >&2
    exit 1
  }
  if [ "$phase_d_start" -le "$phase_c_start" ]; then
    echo "$agent_name: 阶段 D/Phase D 标题 (line $phase_d_start) 必须位于阶段 C/Phase C (line $phase_c_start) 之后" >&2
    exit 1
  fi
  phase_c_body="$(sed -n "${phase_c_start},${phase_d_start}p" "$agent_file")"
  if ! printf '%s' "$phase_c_body" | grep -qF "不扩大也不缩小审查范围"; then
    echo "$agent_name: 阶段 C 缺少背景定向警觉提示「不扩大也不缩小审查范围」" >&2
    exit 1
  fi
  checks=$((checks + 1))

  # 5. 既有契约防误删：语义分组清单行与 filetype_checklists 段必须仍在
  for phrase in "${LEGACY_GUARD_PHRASES[@]}"; do
    if ! grep -qF "$phrase" "$agent_file"; then
      echo "$agent_name: 既有契约被误删，缺少 '$phrase'" >&2
      exit 1
    fi
    checks=$((checks + 1))
  done

  echo "  - $agent_name: OK"
done

echo "PASS: phase15 business background injection (param row + usage rules + commit-message default source + phase C tip; ${#AGENT_FILES[@]} agents, $checks checks)"
