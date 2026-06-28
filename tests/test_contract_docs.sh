#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_FILE="$ROOT_DIR/agents/cc-code-reviewer.md"
FEISHU_FILE="$ROOT_DIR/references/feishu-integration.md"
SKILL_FILE="$ROOT_DIR/skills/cc-code-reviewer/SKILL.md"
AGENTS_FILE="$ROOT_DIR/AGENTS.md"
CLAUDE_FILE="$ROOT_DIR/CLAUDE.md"
EXAMPLES_FILE="$ROOT_DIR/references/examples.md"
FIX_WORKFLOW_FILE="$ROOT_DIR/references/fix-workflow.md"
FIX_SKILL_FILE="$ROOT_DIR/skills/cc-code-fixer/SKILL.md"
FIX_REPORT_FILE="$ROOT_DIR/references/fix-report-format.md"
FIX_FEISHU_FILE="$ROOT_DIR/references/fix-feishu-integration.md"
FIX_EXAMPLES_FILE="$ROOT_DIR/references/fix-examples.md"
IGNORE_SKILL_FILE="$ROOT_DIR/skills/cc-code-ignore/SKILL.md"
IGNORE_WORKFLOW_FILE="$ROOT_DIR/references/ignore-workflow.md"
ARCHITECTURE_PNG="$ROOT_DIR/docs/assets/architecture-overview.png"
ARCHITECTURE_SVG="$ROOT_DIR/docs/assets/architecture-overview.svg"
MARKETPLACE_FILE="$ROOT_DIR/.claude-plugin/marketplace.json"
PLUGIN_FILE="$ROOT_DIR/.claude-plugin/plugin.json"
DD="--"
MODE_BYPASS_TOKEN="FAST_""MODE"
PARAMS_BYPASS_TOKEN="FAST_""PARAMS"
QUICK_START_CN="快速""启动"
BYPASS_PHRASES_CN="无需人工""交互|跳过所有""交互|参数校验""失败|禁止降级为交互式""模式"
SCAN_BYPASS_PATTERN="${MODE_BYPASS_TOKEN}|${PARAMS_BYPASS_TOKEN}|${QUICK_START_CN}|${BYPASS_PHRASES_CN}|${DD}type|${DD}scope|${DD}upload|${DD}branch|${DD}concurrency"

require_literal() {
  local file="$1"
  local text="$2"
  local message="$3"
  if ! grep -Fq "$text" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

# require_match <message> <pattern> <file> [file...]
# 带失败信息的 grep 断言：message 必须作为第一个参数，便于定位失败契约。
# 失败时输出原因、期望 pattern 和第一个未命中的文件。
require_match() {
  local message="$1"
  local pattern="$2"
  shift 2
  local file
  for file in "$@"; do
    [ -n "$file" ] || continue
    if ! grep -Eq "$pattern" "$file"; then
      echo "$message: 未匹配 /$pattern/ in $file" >&2
      exit 1
    fi
  done
}

grep -q "### 第三步之后：持久化报告文件" "$AGENT_FILE"
grep -q "REPORT_FILENAME" "$AGENT_FILE"
grep -q "所有上传和本地输出都必须复用同一个 Markdown 文件" "$AGENT_FILE"

if grep -q 'field-create .*"name":"备注","type":"text"' "$FEISHU_FILE"; then
  echo "默认主字段会重命名为备注，不应再创建重复的备注字段" >&2
  exit 1
fi

grep -q 'field-update .*"name":"备注","type":"text"' "$FEISHU_FILE"
require_match "飞书集成文档必须声明字段总数" "共 17 个字段" "$FEISHU_FILE"
if grep -q "负责人" "$FEISHU_FILE"; then
  echo "scan-stage Feishu Base schema must not include 负责人" >&2
  exit 1
fi

grep -q "### 第一步：提取项目路径" "$SKILL_FILE"
grep -q "优先提取 Git URL" "$SKILL_FILE"

for scan_contract_file in "$SKILL_FILE" "$EXAMPLES_FILE" "$AGENTS_FILE" "$CLAUDE_FILE"; do
  if grep -qE "$SCAN_BYPASS_PATTERN" "$scan_contract_file"; then
    echo "scan contract must be interaction-only; remove command-parameter bypass compatibility from $scan_contract_file" >&2
    exit 1
  fi
done

grep -q "🧩 技术栈扫描" "$SKILL_FILE"
grep -q "识别数量" "$SKILL_FILE"
grep -q "| 技术栈 | 识别证据 | 建议维度 | 专项规则 |" "$SKILL_FILE"
grep -q "dependency:file:" "$SKILL_FILE"
grep -q "另有 {N} 个" "$SKILL_FILE"
grep -q "完整结果已注入子 agent" "$SKILL_FILE"
grep -q "phase5-preview-recent-commits" "$SKILL_FILE"
grep -q "最近提交概览" "$SKILL_FILE"
grep -q "prompt: 注入审查参数表 + 审查参考文件路径 + 项目概况 + 增量数据" "$SKILL_FILE"
grep -q "| 审查框架路径 | {REVIEW_FRAMEWORK_PATH} |" "$SKILL_FILE"
grep -q "| 报告格式路径 | {REPORT_FORMAT_PATH} |" "$SKILL_FILE"
grep -q 'REVIEW_FRAMEWORK_PATH=.*references/languages/java/review-framework.md' "$SKILL_FILE"
grep -q 'REPORT_FORMAT_PATH=.*references/report-format.md' "$SKILL_FILE"
GLOBAL_REFERENCE_LINE="$(grep -n "### 第六步之前：准备审查参考文件路径" "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
TASK_LAUNCH_LINE="$(grep -n "### 第七步：调用子 agent 执行代码审查" "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
if [ -z "$GLOBAL_REFERENCE_LINE" ] || [ -z "$TASK_LAUNCH_LINE" ] || [ "$GLOBAL_REFERENCE_LINE" -ge "$TASK_LAUNCH_LINE" ]; then
  echo "review reference path preparation must be a global pre-Task step before launching the reviewer agent" >&2
  exit 1
fi

grep -q "REVIEW_FRAMEWORK_PATH" "$AGENT_FILE"
grep -q "REPORT_FORMAT_PATH" "$AGENT_FILE"
grep -q "优先读取主 agent 注入的绝对路径" "$AGENT_FILE"
grep -q "IGNORE_RULES_PATH" "$AGENT_FILE"
grep -q "IGNORE_RULES_CONTENT" "$AGENT_FILE"
grep -q "先应用项目 ignore 规则" "$AGENT_FILE"
grep -q "命中 ignore.skip_when 的同类问题，不得输出" "$AGENT_FILE"
require_literal "$SKILL_FILE" "已忽略 {IGNORE_RULE_COUNT} 个问题" "scan preflight summary must show project ignore issue count"
require_literal "$SKILL_FILE" '只统计 `ignore:` 下缩进 2 个空格的 `- name:`' "ignore count must exclude nested applies_to list items"
require_literal "$AGENT_FILE" "不包含 applies_to 下的子列表项" "agent ignore count docs must exclude nested applies_to list items"
require_literal "$EXAMPLES_FILE" "已忽略 2 个问题" "scan examples must show project ignore issue count"
require_literal "$AGENT_FILE" "P0 五项硬门槛（必须全部满足）" "review agent must define all mandatory P0 gates"
require_literal "$AGENT_FILE" "生产可达" "P0 must require a production-reachable path"
require_literal "$AGENT_FILE" "置信度必须为高" "P0 must require high confidence"
require_literal "$AGENT_FILE" "事故级影响" "P0 must require incident-level impact"
require_literal "$AGENT_FILE" "缺少有效防护" "P0 must account for effective mitigations"
require_literal "$AGENT_FILE" "阻断发布" "P0 must be release-blocking"
require_literal "$AGENT_FILE" "证据成立但影响未达到事故级" "confirmed non-P0 findings must downgrade to P1"
require_literal "$AGENT_FILE" "归入待确认" "unproven high-risk findings must move to pending confirmation"
require_literal "$AGENT_FILE" "不得因为未通过 P0 门槛而静默丢弃" "non-fast modes must preserve downgraded findings"
require_literal "$AGENT_FILE" "fast 模式无条件只输出满足 P0 五项硬门槛的 P0；P1、P2、P3 和待确认均不输出" "fast mode must output only fully qualified P0 findings"
if grep -Fq "置信度不影响级别判断" "$AGENT_FILE"; then
  echo "confidence must participate in severity classification; remove the obsolete rule" >&2
  exit 1
fi

BATCH_P0_TEMPLATE="$(awk '
  /^## Batch 发现清单输出格式$/ { in_batch_format = 1; next }
  in_batch_format && /^### P0 \|/ { in_p0_template = 1 }
  in_p0_template && /^### P[1-3] \|/ { exit }
  in_p0_template { print }
' "$AGENT_FILE")"
if [ -z "$BATCH_P0_TEMPLATE" ]; then
  echo "batch finding format must contain a structured P0 template" >&2
  exit 1
fi
for batch_p0_field in \
  "置信度：高" \
  "生产可达路径：" \
  "事故级影响：" \
  "有效防护核查：" \
  "阻断发布理由："; do
  if ! printf '%s\n' "$BATCH_P0_TEMPLATE" | grep -Fq -- "$batch_p0_field"; then
    echo "batch P0 template must include audit field: $batch_p0_field" >&2
    exit 1
  fi
done

require_literal "$EXAMPLES_FILE" "高置信已证实：生产订单请求参数直达未参数化 SQL，无有效校验或绑定防护，可破坏关键订单数据，必须阻断发布" "large-repo SQL injection P0 example must summarize all five gates"
require_literal "$EXAMPLES_FILE" "高置信已证实：生产支付链路发生部分提交，无回滚或补偿防护，可造成资金错误，必须阻断发布" "large-repo transaction P0 example must summarize all five gates"
require_literal "$ROOT_DIR/references/languages/java/review-framework.md" "P0 五项硬门槛" "review framework must share the strict P0 contract"
require_literal "$ROOT_DIR/references/report-format.md" "P0 证据门槛" "report format must require P0 gate evidence"
require_literal "$ROOT_DIR/references/report-format.md" '**置信度**：高 | **所属维度**：维度名称' "P0 report template must require high confidence"

grep -q "phase9-collect-fix-metadata" "$FIX_SKILL_FILE" "$FIX_WORKFLOW_FILE" "$FIX_REPORT_FILE"
if [ ! -f "$ARCHITECTURE_PNG" ]; then
  echo "架构总览图缺失: $ARCHITECTURE_PNG" >&2
  exit 1
fi
if [ -f "$ARCHITECTURE_SVG" ]; then
  echo "architecture overview is imagegen PNG-only; SVG source should not be kept" >&2
  exit 1
fi

grep -q "🧩 技术栈扫描" "$EXAMPLES_FILE"
grep -q "飞书保存不可用" "$EXAMPLES_FILE"
grep -q "报告已保存到" "$EXAMPLES_FILE"
grep -q "项目 ignore 命中" "$EXAMPLES_FILE"

if [ ! -f "$IGNORE_SKILL_FILE" ]; then echo "ignore skill 缺失: $IGNORE_SKILL_FILE" >&2; exit 1; fi
if [ ! -f "$IGNORE_WORKFLOW_FILE" ]; then echo "ignore workflow 缺失: $IGNORE_WORKFLOW_FILE" >&2; exit 1; fi
require_match "ignore 文档必须声明 AI 指令型语义" "AI 指令型 ignore 文件" "$IGNORE_SKILL_FILE" "$IGNORE_WORKFLOW_FILE"
require_match "ignore 文档必须包含默认文件路径" '\.cc-code-reviewer/ignore/issues\.yml' "$IGNORE_SKILL_FILE" "$IGNORE_WORKFLOW_FILE" "$SKILL_FILE" "$AGENT_FILE"
# 注意：以下断言原本就是 grep -q 多文件"任一命中"语义（skill 与 workflow 措辞不同），
# 不能用 require_match（它要求所有文件命中），故保留 grep -q 但补充失败说明。
if ! grep -q "不存报告编号" "$IGNORE_SKILL_FILE" "$IGNORE_WORKFLOW_FILE"; then
  echo "ignore 文档必须声明不存报告编号 (skill 与 workflow 任一命中即可)" >&2
  exit 1
fi
require_match "ignore workflow YAML 必须包含 name 字段示例" "name:" "$IGNORE_WORKFLOW_FILE"
require_match "ignore workflow YAML 必须包含 applies_to 字段示例" "applies_to:" "$IGNORE_WORKFLOW_FILE"
require_match "ignore workflow YAML 必须包含 skip_when 字段示例" "skip_when:" "$IGNORE_WORKFLOW_FILE"
require_match "ignore 文档必须支持飞书 Base 来源" "飞书 Base" "$IGNORE_SKILL_FILE" "$IGNORE_WORKFLOW_FILE"
require_match "ignore 文档必须支持本地 Markdown 来源" "本地 Markdown" "$IGNORE_SKILL_FILE" "$IGNORE_WORKFLOW_FILE"
require_match "ignore 文档必须描述用户指定问题编号流程" "用户指定问题编号" "$IGNORE_SKILL_FILE" "$IGNORE_WORKFLOW_FILE"

grep -qx "# Fix Workflow" "$FIX_WORKFLOW_FILE"
grep -qx "## Fix Input Normalization" "$FIX_WORKFLOW_FILE"
grep -qx "## Preflight Sequence" "$FIX_WORKFLOW_FILE"
grep -qx "## Execution Route Selection" "$FIX_WORKFLOW_FILE"
grep -qx "## Direct Fix Flow" "$FIX_WORKFLOW_FILE"
grep -qx "## Superpowers Flow" "$FIX_WORKFLOW_FILE"
grep -qx "## Degraded Mode" "$FIX_WORKFLOW_FILE"
grep -qx "## Fix Scope Rules" "$FIX_WORKFLOW_FILE"
grep -qx "## Workspace Rules" "$FIX_WORKFLOW_FILE"
grep -q "brainstorming" "$FIX_WORKFLOW_FILE"
grep -q "test-driven-development" "$FIX_WORKFLOW_FILE"
grep -q "verification-before-completion" "$FIX_WORKFLOW_FILE"
grep -q "交互确认是硬门禁" "$FIX_WORKFLOW_FILE"
grep -q "Superpowers 可选" "$FIX_WORKFLOW_FILE"
grep -q "直接修复路线必须确认工作区策略" "$FIX_WORKFLOW_FILE"
grep -q "subagent-driven-development" "$FIX_WORKFLOW_FILE"
grep -q "无已归一化问题上下文时必须停止修复" "$FIX_WORKFLOW_FILE" "$FIX_FEISHU_FILE"
grep -q "Other/free-form 中粘贴" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"
grep -q "一次 AskUserQuestion 收集问题清单位置" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE"
grep -q "根据输入动态识别" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"
grep -q "不得先让用户选择本地 Markdown、飞书云文档或飞书多维表格" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE"
if grep -q "请提供本次待修复问题确认清单的来源" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"; then
  echo "fix flow must collect a single source/path input and infer the source type dynamically" >&2
  exit 1
fi
grep -q "本地 Markdown 必须直接读取文件内容" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE"
grep -q "不得使用 Python 脚本读取飞书云文档或飞书多维表格" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_FEISHU_FILE"
grep -q "飞书云文档和飞书多维表格不得调用.*phase6-detect-fix-input" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE"
grep -q "状态过滤" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_FEISHU_FILE"
grep -q "STATUS_FILTERED_ISSUES" "$FIX_WORKFLOW_FILE"
grep -q "SKIPPED_STATUS_COUNTS" "$FIX_WORKFLOW_FILE"
grep -q "已修复.*已忽略.*不适用" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE"
grep -q "已修复项不得出现在表格中" "$FIX_EXAMPLES_FILE"
grep -q "跳过记录不得出现在待确认问题表格" "$FIX_FEISHU_FILE"
grep -q "一个写回原始来源选项" "$FIX_WORKFLOW_FILE"
grep -q "创建独立本地 Markdown 修复报告" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"
grep -q "创建独立飞书云文档修复报告" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"
grep -q "创建独立飞书多维表格修复报告" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"
grep -q "写回原始本地 Markdown" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"
grep -q "写回原始飞书云文档" "$FIX_SKILL_FILE"
grep -q "写回原始飞书多维表格" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"
grep -q "不得在修复完成后追加新的回写确认问题" "$FIX_WORKFLOW_FILE"
grep -q "不得修改原始问题清单来源" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_FEISHU_FILE" "$FIX_REPORT_FILE"
grep -q "FIX_COMPLETED_AT" "$FIX_SKILL_FILE" "$FIX_WORKFLOW_FILE" "$FIX_REPORT_FILE" "$FIX_FEISHU_FILE"
grep -q "FIX_ACTOR" "$FIX_SKILL_FILE" "$FIX_WORKFLOW_FILE" "$FIX_REPORT_FILE" "$FIX_FEISHU_FILE"
grep -q "修复人" "$FIX_SKILL_FILE" "$FIX_WORKFLOW_FILE" "$FIX_REPORT_FILE" "$FIX_FEISHU_FILE" "$FIX_EXAMPLES_FILE"
grep -q "不得再询问用户" "$FIX_SKILL_FILE" "$FIX_WORKFLOW_FILE"
if grep -q "是否把修复状态更新回问题清单源" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"; then
  echo "fix flow must not add a separate post-repair writeback AskUserQuestion" >&2
  exit 1
fi
if grep -q "SOURCE_STATUS_WRITEBACK" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_REPORT_FILE"; then
  echo "source writeback must be folded into OUTPUT_TARGET, not tracked as a separate prompt" >&2
  exit 1
fi
if grep -qE "模型 / effort|MODEL_PREFERENCE|EFFORT_PREFERENCE" "$FIX_WORKFLOW_FILE"; then
  echo "fix workflow must not require model/effort confirmation" >&2
  exit 1
fi
if grep -q "$QUICK_START_CN" "$FIX_WORKFLOW_FILE"; then
  echo "fix workflow must not mention command-parameter bypass flow" >&2
  exit 1
fi

grep -qx "# 修复报告格式规范" "$FIX_REPORT_FILE"
grep -q "## 修复配置快照" "$FIX_REPORT_FILE"
grep -q "## 修复输入摘要" "$FIX_REPORT_FILE"
grep -q "## 已修复问题" "$FIX_REPORT_FILE"
grep -q "## 部分修复问题" "$FIX_REPORT_FILE"
grep -q "## 未修复问题" "$FIX_REPORT_FILE"
grep -q "## 测试变更" "$FIX_REPORT_FILE"
grep -q "## 验证命令与结果" "$FIX_REPORT_FILE"
grep -q "## 代码变更摘要" "$FIX_REPORT_FILE"
grep -q "## 飞书回写结果" "$FIX_REPORT_FILE"
grep -q "## 后续建议" "$FIX_REPORT_FILE"

grep -qx "# Fix Feishu Integration" "$FIX_FEISHU_FILE"
grep -qx "## 读取飞书云文档" "$FIX_FEISHU_FILE"
grep -qx "## 读取飞书多维表格" "$FIX_FEISHU_FILE"
grep -qx "## 更新飞书多维表格" "$FIX_FEISHU_FILE"
grep -qx "## 创建修复报告云文档" "$FIX_FEISHU_FILE"
grep -qx "## 失败降级" "$FIX_FEISHU_FILE"
grep -q "修复状态" "$FIX_FEISHU_FILE"
grep -q "修复时间" "$FIX_FEISHU_FILE"
grep -q "修复分支" "$FIX_FEISHU_FILE"
grep -q "所属维度" "$FIX_FEISHU_FILE"
grep -q "置信度" "$FIX_FEISHU_FILE"
grep -q "证据" "$FIX_FEISHU_FILE"
grep -q "影响" "$FIX_FEISHU_FILE"
grep -q "备注" "$FIX_FEISHU_FILE"
grep -q "lark-cli base" "$FIX_FEISHU_FILE"
grep -q "wiki spaces get_node" "$FIX_FEISHU_FILE" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE"
grep -q "obj_token" "$FIX_FEISHU_FILE" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE"
grep -q "查询参数 .*table" "$FIX_FEISHU_FILE" "$FIX_WORKFLOW_FILE"
grep -q "查询参数 .*view" "$FIX_FEISHU_FILE" "$FIX_WORKFLOW_FILE"
grep -q -- "--table-id" "$FIX_FEISHU_FILE" "$FIX_SKILL_FILE"
grep -q "docs +fetch --api-version v2 --doc" "$FIX_FEISHU_FILE"
grep -q "docs +create" "$FIX_FEISHU_FILE"
grep -q -- "--api-version v2" "$FIX_FEISHU_FILE"
grep -q -- "--doc-format markdown" "$FIX_FEISHU_FILE"
grep -q -- "--content @fix-report" "$FIX_FEISHU_FILE"
if grep -q "docs +fetch --url" "$FIX_FEISHU_FILE" "$FIX_EXAMPLES_FILE"; then
  echo "Task 4 fixer docs must use docs +fetch --api-version v2 --doc, not --url" >&2
  exit 1
fi
if grep -A6 "docs +create" "$FIX_FEISHU_FILE" | grep -q -- "--title"; then
  echo "Task 4 fixer docs must not use unsupported docs +create --title" >&2
  exit 1
fi
if grep -q -- "--markdown @" "$FIX_FEISHU_FILE" "$FIX_EXAMPLES_FILE"; then
  echo "Task 4 fixer docs must create docs with docs +create --api-version v2 --doc-format markdown --content" >&2
  exit 1
fi
if grep -q "+record-update" "$FIX_FEISHU_FILE" "$FIX_EXAMPLES_FILE"; then
  echo "Task 4 fixer docs must use base +record-upsert --record-id, not +record-update" >&2
  exit 1
fi
grep -q "+record-upsert" "$FIX_FEISHU_FILE" "$FIX_EXAMPLES_FILE"

grep -qx "# Fix Examples" "$FIX_EXAMPLES_FILE"
grep -qx "## 本地 Markdown 报告" "$FIX_EXAMPLES_FILE"
grep -qx "## 飞书多维表格" "$FIX_EXAMPLES_FILE"
grep -q "待修复问题确认清单" "$FIX_EXAMPLES_FILE"
grep -q "问题清单位置" "$FIX_EXAMPLES_FILE"
grep -q "| 问题ID | 严重级别 | 维度 | 问题摘要 | 修复建议 |" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"
grep -q "不要输出项目符号列表" "$FIX_SKILL_FILE"
grep -q "问题摘要和修复建议必须压缩成终端可扫读的短句" "$FIX_SKILL_FILE"
if grep -q "| 问题ID | 严重级别 | 维度 | 置信度 | 位置 | 问题摘要 | 修复建议 |" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"; then
  echo "fix issue confirmation table must use compact terminal table columns, not the old wide table" >&2
  exit 1
fi
if grep -q "$QUICK_START_CN" "$FIX_EXAMPLES_FILE"; then
  echo "fix examples must not document command-parameter bypass flow" >&2
  exit 1
fi

grep -q "模式判定" "$FIX_SKILL_FILE"
grep -q "phase6-detect-fix-input" "$FIX_SKILL_FILE"
grep -q "phase7-detect-superpowers" "$FIX_SKILL_FILE"
grep -q "修复输入解析完成" "$FIX_SKILL_FILE"
grep -q "AskUserQuestion" "$FIX_SKILL_FILE"
grep -q "待修复问题确认清单" "$FIX_SKILL_FILE"
grep -q "问题清单位置" "$FIX_SKILL_FILE"
grep -q "问题清单表格" "$FIX_SKILL_FILE"
grep -q "执行方式" "$FIX_SKILL_FILE"
grep -q "直接开始修复" "$FIX_SKILL_FILE"
grep -q "使用 Superpowers 修复" "$FIX_SKILL_FILE"
grep -q "SUPERPOWERS_AVAILABLE=true 时才展示" "$FIX_SKILL_FILE"
grep -q "请选择直接修复使用的工作区策略" "$FIX_SKILL_FILE"
grep -q "确认执行计划" "$FIX_SKILL_FILE"
grep -q "brainstorming" "$FIX_SKILL_FILE"
grep -q "subagent-driven-development" "$FIX_SKILL_FILE"
if grep -qE "${MODE_BYPASS_TOKEN}|${PARAMS_BYPASS_TOKEN}|${QUICK_START_CN}|\`${DD}scope\`|\`${DD}workspace\`|\`${DD}strategy\`" "$FIX_SKILL_FILE"; then
  echo "cc-code-fixer must not contain command-parameter bypass syntax" >&2
  exit 1
fi

# Fix agent removed: fix stage delegates to Superpowers (brainstorming → subagent-driven-development)
# Key contracts now live in fix-report-format.md and fix-feishu-integration.md
grep -q "fix-report-{PROJECT_NAME}-{YYYYMMDD-HHmmss}.md" "$FIX_REPORT_FILE"
grep -q "fix-report-" "$FIX_FEISHU_FILE" "$FIX_EXAMPLES_FILE"
if grep -qE "minimal|with-tests|目标分支|输出选项|TARGET_BRANCH|OUTPUT_OPTION|fixed|partially fixed|not fixed|not applicable|needs human confirmation|code-fix-report" "$FIX_REPORT_FILE" "$FIX_FEISHU_FILE" "$FIX_EXAMPLES_FILE"; then
  echo "cc-code-fixer contracts must use unified strategy names, Chinese statuses, and fix-report filenames" >&2
  exit 1
fi

PLUGIN_VERSION="$(grep -E '"version":' "$PLUGIN_FILE" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')"
MARKETPLACE_VERSION="$(grep -E '"version":' "$MARKETPLACE_FILE" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')"
MARKETPLACE_PLUGIN_VERSION="$(grep -E '"version":' "$MARKETPLACE_FILE" | sed -n 2p | sed 's/.*"version": *"\([^"]*\)".*/\1/')"

# 版本号不再硬编码：只校验三处版本互相一致且非空。
# 发版时只需改 plugin.json + marketplace.json 两个文件，本测试自动跟随。
version_assert() {
  local left="$1" right="$2" label="$3"
  if [ "$left" != "$right" ]; then
    echo "版本不一致 ($label): '$left' != '$right'" >&2
    exit 1
  fi
  if [ -z "$left" ]; then
    echo "版本号为空 ($label)，请检查 plugin.json / marketplace.json 是否包含 \"version\" 字段" >&2
    exit 1
  fi
}
version_assert "$PLUGIN_VERSION" "$MARKETPLACE_VERSION" "plugin.json vs marketplace.json 顶层"
version_assert "$PLUGIN_VERSION" "$MARKETPLACE_PLUGIN_VERSION" "plugin.json vs marketplace.json plugin 条目"
version_assert "$PLUGIN_VERSION" "$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$PLUGIN_FILE" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')" "plugin.json 自身可解析"
require_match "plugin.json 必须声明 code-fixer 关键字" "code-fixer" "$PLUGIN_FILE"
require_match "plugin.json 必须声明 code-fix skill" '"code-fix"' "$PLUGIN_FILE"
require_match "marketplace.json 必须声明 code-fix skill" '"code-fix"' "$MARKETPLACE_FILE"
require_match "marketplace.json 描述必须包含 report-driven fixing" "report-driven fixing" "$MARKETPLACE_FILE"

# === Batch scanning contracts ===

# === Maven large repository batching contracts ===

grep -q "phase10-detect-code-intelligence.sh" "$SKILL_FILE"
grep -q "phase11-plan-large-batches.sh" "$SKILL_FILE"
grep -q "phase12-merge-large-batches.sh" "$SKILL_FILE"
grep -q "phase13-show-large-batch-status.sh" "$SKILL_FILE"

grep -q "Maven 多模块" "$SKILL_FILE"
grep -q "存量审查" "$SKILL_FILE"
grep -q "全量代码" "$SKILL_FILE"
grep -q "TOTAL_JAVA_LOC >= 120000" "$SKILL_FILE"

grep -q "TARGET_BATCH_LOC = 50000" "$SKILL_FILE"
grep -q "SOFT_MIN_BATCH_LOC = 30000" "$SKILL_FILE"
grep -q "SOFT_MAX_BATCH_LOC = 50000" "$SKILL_FILE"
grep -q "HARD_MAX_BATCH_LOC = 50000" "$SKILL_FILE"
require_literal "$SKILL_FILE" "semantic-cost batching" "large repo strategy must be semantic-cost batching"
require_literal "$SKILL_FILE" "review_cost = java_loc + java_file_count * 25" "review cost formula must be documented"
require_literal "$SKILL_FILE" "TARGET_BATCH_COST = 52000" "target review cost baseline must be documented"
require_literal "$SKILL_FILE" "HARD_MAX_BATCH_COST = 65000" "hard review cost baseline must be documented"
require_match "SKILL 必须说明批次成本按 CONTEXT_SCALE 缩放" "CONTEXT_SCALE" "$SKILL_FILE"
require_literal "$SKILL_FILE" "context_roots" "large repo plan must include bounded context roots"
require_literal "$SKILL_FILE" "context cost" "large repo context cost must be bounded"
require_literal "$SKILL_FILE" "work units" "large repo planner must use work units"
require_literal "$SKILL_FILE" "oversized modules are split before plan emission" "oversized modules must be split, not only marked"
require_literal "$SKILL_FILE" "tiny tail batches" "tiny tail batches must be rebalanced"

require_literal "$AGENT_FILE" "context_roots" "batch agent must understand context roots"
require_literal "$AGENT_FILE" "Formal findings must point to locations inside scan_roots" "batch findings must stay inside scan roots"
require_literal "$AGENT_FILE" "context_roots are read-only context" "agent must not count context roots as reviewed"
require_literal "$AGENT_FILE" '`src/main/java` 生产 Java 文件作为本批正式审查范围' "batch agent must scan only production Java sources"
require_literal "$AGENT_FILE" '`src/test/java` 只能作为测试质量判断的只读上下文' "batch agent must keep test sources contextual"

require_match "planner 必须定义目标批次成本（基于 52000 基准 × scale）" '52000 \* CONTEXT_SCALE' "$ROOT_DIR/scripts/phase11-plan-large-batches.sh"
require_match "planner 必须定义硬上限成本（基于 65000 基准 × scale）" '65000 \* CONTEXT_SCALE' "$ROOT_DIR/scripts/phase11-plan-large-batches.sh"
require_match "planner 必须接收 CONTEXT_SCALE 参数" "CONTEXT_SCALE" "$ROOT_DIR/scripts/phase11-plan-large-batches.sh"
require_literal "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" "review_cost" "planner must compute review cost"
require_literal "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" "context_roots" "planner must emit context roots"
require_literal "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" "semantic-cost-batching" "planner must emit semantic-cost strategy"
require_literal "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" "SELECTED_MODULE_OUTSIDE_PROJECT" "planner must reject selected modules outside project root"
require_match "status 须定义批次成本基准（随 CONTEXT_SCALE 缩放）" 'TARGET_REVIEW_COST' "$ROOT_DIR/scripts/core/show-batch-status.sh"
require_literal "$ROOT_DIR/scripts/core/merge-batch-results.sh" "RUN_BATCH_IDS" "merge must honor the current-run batch set"
require_literal "$ROOT_DIR/scripts/core/merge-batch-results.sh" "[合并阻塞]" "merge must report blocked current-run batches"
require_literal "$ROOT_DIR/scripts/core/merge-batch-results.sh" "批次状态总览" "merge report must include all batch statuses"
require_literal "$ROOT_DIR/scripts/core/merge-batch-results.sh" "report_title" "merge summary must expose a cloud-doc title"
require_literal "$ROOT_DIR/scripts/core/merge-batch-results.sh" "dedupe_issue_blocks" "merge must dedupe included batch findings"
require_literal "$ROOT_DIR/scripts/core/merge-batch-results.sh" "INCLUDED_BATCHES" "merge completeness must depend on included batches"
require_literal "$ROOT_DIR/scripts/core/merge-batch-results.sh" "审查配置快照" "merge report must include config snapshot section"
require_literal "$ROOT_DIR/scripts/core/merge-batch-results.sh" "覆盖限制与未审查范围" "merge report must disclose coverage limitations"
require_literal "$SKILL_FILE" "合并脚本等待本轮批次进入终态" "skill must document merge waiting"
require_literal "$SKILL_FILE" 'failed`，或 `completed` 但结果文件缺失' "skill must block failed or missing batch results"
require_literal "$SKILL_FILE" "summary.json.report_title" "skill must validate merged cloud-doc title"
require_literal "$SKILL_FILE" "SELECTED_MODULE_OUTSIDE_PROJECT" "skill must document selected-module boundary rejection"
require_literal "$SKILL_FILE" "已纳入合并的批次数" "skill must document staged/full merge based on included batches"
require_literal "$AGENTS_FILE" "report_title" "AGENTS must document merged report title contract"
require_literal "$CLAUDE_FILE" "report_title" "CLAUDE must document merged report title contract"
require_literal "$AGENTS_FILE" "Selected module paths must be relative paths inside" "AGENTS must document selected-module boundary"
require_literal "$CLAUDE_FILE" "Selected module paths must be relative paths inside" "CLAUDE must document selected-module boundary"
require_literal "$ROOT_DIR/references/report-format.md" "[合并阻塞]" "report format must document blocked merge reports"
require_literal "$ROOT_DIR/references/report-format.md" "分批合并报告格式" "report format must document deterministic merge report shape"

grep -q "pending.*待执行" "$SKILL_FILE"
grep -q "running.*执行中" "$SKILL_FILE"
grep -q "completed.*已完成" "$SKILL_FILE"
grep -q "failed.*失败待重试" "$SKILL_FILE"
FORBIDDEN_BATCH_STATE_DECL_PATTERN='("status"[[:space:]]*:[[:space:]]*"(partial|stale|skipped)")|((status[[:space:]_-]*(enum|state|list|value)|batch[[:space:]_-]*status|state[[:space:]_-]*(enum|list|value)|状态(枚举|列表|值)|批次状态)[^[:cntrl:]]{0,80}(partial|stale|skipped|部分完成|中断待确认|已跳过))|((partial|stale|skipped|部分完成|中断待确认|已跳过)[^[:cntrl:]]{0,80}(status[[:space:]_-]*(enum|state|list|value)|batch[[:space:]_-]*status|state[[:space:]_-]*(enum|list|value)|状态(枚举|列表|值)|批次状态))'
if grep -qE "$FORBIDDEN_BATCH_STATE_DECL_PATTERN" "$SKILL_FILE" "$AGENT_FILE"; then
  echo "large repo v1 status enum must only use pending/running/completed/failed" >&2
  exit 1
fi
if awk '
  /pending|running|completed|failed|BATCH_STATUS_PATH|batch status|large repo status|large repository status|large repo v1|status\.json|批次状态|大仓状态|大型仓库状态|状态文件/ {
    for (i = NR - 6; i <= NR + 6; i++) {
      if (i > 0) {
        near_status[i] = 1
      }
    }
  }
  { lines[NR] = $0 }
  END {
    for (i = 1; i <= NR; i++) {
      if (near_status[i]) {
        print lines[i]
      }
    }
  }
' "$SKILL_FILE" "$AGENT_FILE" | grep -qE "reviewed_java_files|remaining_files"; then
  echo "large repo v1 batch status contract must not use file-level reviewed manifests" >&2
  exit 1
fi

grep -q "scan_roots" "$SKILL_FILE"
grep -q "正式问题.*scan_roots" "$SKILL_FILE"
grep -q "jdtls.*跨目录" "$SKILL_FILE"
grep -q "jdtls-lsp 可用时必须使用" "$SKILL_FILE"
grep -q "跨批依赖待复核" "$SKILL_FILE"

grep -q "BATCH_PLAN_PATH" "$AGENT_FILE"
grep -q "BATCH_STATUS_PATH" "$AGENT_FILE"
grep -q "BATCH_RESULT_PATH" "$AGENT_FILE"
grep -q "scan_roots" "$AGENT_FILE"
grep -q "正式问题.*scan_roots" "$AGENT_FILE"
grep -q "jdtls-lsp 可用时必须使用" "$AGENT_FILE"
grep -q "definition、references、implementations、call hierarchy" "$AGENT_FILE"
grep -q "语义增强使用情况" "$AGENT_FILE"
grep -q "跨批依赖待复核" "$AGENT_FILE"

# Agent must support batch output mode
grep -q "审查输出模式" "$AGENT_FILE"
grep -q "仅发现清单" "$AGENT_FILE"
grep -q "完整报告" "$AGENT_FILE"
grep -q "批次编号" "$AGENT_FILE"
grep -q "BATCH_INDEX" "$AGENT_FILE"
grep -q "BATCH_FILE_LIST" "$AGENT_FILE"
grep -q "review-batch-" "$AGENT_FILE"

# Agent must skip stages in batch mode
grep -q "阶段 A.*跳过" "$AGENT_FILE"
grep -q "阶段 B.*跳过" "$AGENT_FILE"

# Skill must have batch trigger formula
grep -q "BATCH_MODE" "$SKILL_FILE"
grep -q "estimated_tokens" "$SKILL_FILE"
grep -q "100000" "$SKILL_FILE"

# Stock review entry must expose full and selected-module choices directly.
require_literal "$SKILL_FILE" 'label: "增量审查"' "review entry must keep incremental review"
require_literal "$SKILL_FILE" 'label: "全量审查"' "review entry must expose full stock review directly"
require_literal "$SKILL_FILE" 'label: "指定模块"' "review entry must expose selected-module stock review directly"
require_literal "$SKILL_FILE" "STOCK_REVIEW_STRATEGY" "stock review flow must capture the selected batching strategy"
require_literal "$SKILL_FILE" "module-sequential" "stock review flow must support per-module sequential batching"
require_literal "$SKILL_FILE" "ai-planned" "stock review flow must support AI planned batching"
require_literal "$SKILL_FILE" "按所选模块依次启动" "stock review strategy must describe per-module execution"
require_literal "$SKILL_FILE" "AI 智能规划分批" "stock review strategy must describe smart batching"
require_literal "$SKILL_FILE" "不得把每个模块都作为 AskUserQuestion option" "module selection must avoid oversized AskUserQuestion payloads"
require_literal "$SKILL_FILE" "最多 3 个固定选项" "module selection AskUserQuestion must stay bounded"
require_literal "$SKILL_FILE" "Other/free-form" "module selection must allow manual free-form module paths"
if grep -q "模块超过 10 个时展示前 9 个" "$SKILL_FILE"; then
  echo "module selection must not dynamically add many module options" >&2
  exit 1
fi
require_literal "$SKILL_FILE" "Maven 多模块项目不得使用内联 Bash 数组分批" "Maven batch planning must use deterministic planner scripts"
require_literal "$SKILL_FILE" "phase11-plan-large-batches.sh" "Maven batch planning must call phase11 planner"
require_literal "$SKILL_FILE" "phase11-plan-file-batches.sh" "single-module and non-Maven batching must call deterministic file planner"
require_literal "$SKILL_FILE" 'Maven 多模块存量分批绝不调用 `phase11-plan-file-batches.sh`' "Maven selected-module batching must never fall back to whole-project file planner"
require_literal "$SKILL_FILE" "即使只选择一个模块" "single selected Maven module must still use the scoped Maven planner"
require_literal "$SKILL_FILE" "简要分批计划" "file batching must show a concise batch plan before concurrency selection"
require_literal "$SKILL_FILE" "BATCH_FILE_LIST_DIR" "file batching must expose batch file list directory for batch agents"
if grep -q "当 BATCH_MODE=true 时，主 skill 在 prompt 中执行以下步骤（不使用脚本）" "$SKILL_FILE"; then
  echo "batch calculation must not instruct the agent to improvise inline shell batching" >&2
  exit 1
fi
if grep -q "current_batch_tokens" "$SKILL_FILE" || grep -q "batch_file_counts" "$SKILL_FILE" || grep -q "python3 << 'EOF'" "$SKILL_FILE"; then
  echo "batch calculation must not contain fragile inline shell array/token batching variables" >&2
  exit 1
fi

MODE_PICK_LINE="$(grep -n 'question: "请选择审查模式"' "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
UPLOAD_PICK_LINE="$(grep -n 'question: "请选择审查报告的保存方式"' "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
ENTRY_PICK_LINE="$(grep -n 'question: "请选择本次审查入口"' "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
require_literal "$SKILL_FILE" 'label: "fast（仅输出 P0）"' "fast option must state its P0-only output"
require_literal "$SKILL_FILE" '只报告已证实、足以阻断上线的 P0；P1/P2/P3 和待确认项均不输出' "fast option must explain excluded severities"
require_literal "$SKILL_FILE" 'fast（仅输出 P0） → REVIEW_MODE=fast' "fast option response must normalize to the internal fast enum"
require_literal "$SKILL_FILE" 'standard（推荐） → REVIEW_MODE=standard' "standard option response must normalize to the internal standard enum"
require_literal "$SKILL_FILE" 'deep → REVIEW_MODE=deep' "deep option response must normalize to the internal deep enum"
require_literal "$SKILL_FILE" 'security → REVIEW_MODE=security' "security option response must normalize to the internal security enum"
require_literal "$SKILL_FILE" '输出级别：仅 P0  ← 仅 REVIEW_MODE=fast 时显示' "fast execution plan must repeat the conditional P0-only boundary"
require_literal "$EXAMPLES_FILE" 'fast（仅输出 P0）' "scan examples must show the explicit fast label"
require_literal "$ROOT_DIR/README.md" '仅输出 P0' "README mode table must disclose fast output severity"
require_literal "$AGENTS_FILE" 'fast 模式只输出满足全部 P0 硬门槛的问题' "AGENTS must document fast P0-only behavior"
require_literal "$CLAUDE_FILE" 'fast 模式只输出满足全部 P0 硬门槛的问题' "CLAUDE must document fast P0-only behavior"
if [ -z "$MODE_PICK_LINE" ] || [ -z "$UPLOAD_PICK_LINE" ] || [ -z "$ENTRY_PICK_LINE" ] || [ "$MODE_PICK_LINE" -ge "$UPLOAD_PICK_LINE" ] || [ "$UPLOAD_PICK_LINE" -ge "$ENTRY_PICK_LINE" ]; then
  echo "review mode and report handling must be selected before the review entry" >&2
  exit 1
fi
MODEL_PICK_LINE="$(grep -n 'question: "请选择审查使用的 AI 模型"' "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
if [ -z "$MODEL_PICK_LINE" ]; then
  echo "model selection AskUserQuestion must exist" >&2
  exit 1
fi
# 模型选择已前移到分批之前（第四步之后段），出现在文档的"执行算法"段。
# 断言改为：模型选择必须存在，且文档中必须声明它发生在分批规划之前。
require_match "SKILL 必须声明模型选择在分批之前（时序前提）" "模型选择放在分批之前" "$SKILL_FILE"
grep -q "REVIEW_MODEL" "$SKILL_FILE"
require_literal "$SKILL_FILE" "报告保存方式为多选" "report handling must document multi-select semantics"
require_literal "$SKILL_FILE" "用户可选择本地 Markdown 报告、飞书云文档和飞书多维表格中的任意一个或多个，支持任意组合多选" "dual Feishu upload must be represented by selecting both upload targets"
UPLOAD_MULTISELECT_BLOCK="$(sed -n "${UPLOAD_PICK_LINE},$((UPLOAD_PICK_LINE + 18))p" "$SKILL_FILE")"
if ! printf '%s\n' "$UPLOAD_MULTISELECT_BLOCK" | grep -q -- "- multiSelect: true"; then
  echo "report handling AskUserQuestion must be multi-select" >&2
  exit 1
fi
if grep -q "同时上传两者" "$SKILL_FILE" "$AGENT_FILE" "$FEISHU_FILE" "$EXAMPLES_FILE"; then
  echo "report handling must remove the old combined upload option" >&2
  exit 1
fi

# Skill must have concurrency step
grep -q "选择并发数" "$SKILL_FILE"
grep -q "CONCURRENCY" "$SKILL_FILE"
grep -q "串行执行" "$SKILL_FILE"
grep -q "2 路并发" "$SKILL_FILE"
grep -q "3 路并发" "$SKILL_FILE"
grep -q '默认 `1`' "$SKILL_FILE"
grep -q '1.*2.*3' "$SKILL_FILE"
require_literal "$SKILL_FILE" "并发数必须小于等于本轮实际执行批次数" "concurrency choices must be capped by selected batch count"
require_literal "$SKILL_FILE" "RUN_BATCH_COUNT=1" "single selected batch must force serial concurrency"
require_literal "$SKILL_FILE" "自动设置 `CONCURRENCY=1`" "single selected batch must not ask for concurrency"
require_literal "$SKILL_FILE" "RUN_BATCH_COUNT=2" "two selected batches must hide 3-way concurrency"
if grep -q "5 路并发" "$SKILL_FILE"; then
  echo "batch concurrency options must be 1/2/3, not 1/3/5" >&2
  exit 1
fi

grep -q 'label: "本地 Markdown 报告"' "$SKILL_FILE"
if grep -q 'label: "仅显示报告"' "$SKILL_FILE"; then
  echo "first review result handling option must be local Markdown report, not only chat display" >&2
  exit 1
fi

BATCH_SHOW_LINE="$(grep -n "phase13-show-large-batch-status.sh" "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
BATCH_PICK_LINE="$(grep -n 'question: "请选择本轮执行批次"' "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
CONCURRENCY_LINE="$(grep -n 'question: "请选择并发扫描策略"' "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
if [ -z "$BATCH_SHOW_LINE" ] || [ -z "$BATCH_PICK_LINE" ] || [ -z "$CONCURRENCY_LINE" ] || [ "$BATCH_SHOW_LINE" -ge "$BATCH_PICK_LINE" ] || [ "$BATCH_PICK_LINE" -ge "$CONCURRENCY_LINE" ]; then
  echo "large repo flow must show batch status, then select execution batches, then select concurrency" >&2
  exit 1
fi
grep -q "普通助手消息" "$SKILL_FILE"
grep -q "| 批次 | 状态 | 行数 | 文件数 | 模块 |" "$EXAMPLES_FILE"
grep -q "|------|------|------:|------:|------|" "$EXAMPLES_FILE"
grep -q "用户可见的 Markdown 表格" "$SKILL_FILE"
require_literal "$ROOT_DIR/scripts/core/show-batch-status.sh" "| 批次 | 状态 | 行数 | 文件数 | 模块 |" "batch status script must render a Markdown batch table"
require_literal "$ROOT_DIR/scripts/core/show-batch-status.sh" "|------|------|------:|------:|------|" "batch status table separator should match user-facing Markdown table style"
require_literal "$SKILL_FILE" "模块列必须使用缩略名展示" "batch module column must abbreviate common engineering prefixes"
require_literal "$SKILL_FILE" "去掉共同前缀" "batch module abbreviation must remove shared prefixes"
require_literal "$SKILL_FILE" "不得只依赖 Bash 工具输出" "batch status must be visible in assistant message, not only collapsed Bash output"
require_literal "$SKILL_FILE" "普通助手消息" "batch status table must be reprinted as normal assistant content"
require_literal "$SKILL_FILE" "不得放入代码块" "batch status table must render like tech-stack table"
if grep -q "批次 状态 行数 成本 文件 模块 原因" "$EXAMPLES_FILE" "$SKILL_FILE"; then
  echo "large repo batch status examples must use Markdown table syntax" >&2
  exit 1
fi
require_literal "$SKILL_FILE" "必须根据本轮可执行批次数动态生成" "batch execution options must be dynamic"
require_literal "$SKILL_FILE" "RUNNABLE_COUNT=1" "single runnable batch must skip batch-selection question"
require_literal "$SKILL_FILE" "不调用 AskUserQuestion" "single runnable batch must not ask for batch selection"
require_literal "$SKILL_FILE" "但描述里又显示" "batch options must not show impossible fixed limits"
require_literal "$ROOT_DIR/scripts/core/show-batch-status.sh" "display_dynamic_plan_rows" "batch status script must render dynamic execution plans"
require_literal "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" 'RUN_ID="$RUN_TIMESTAMP-$(branch_slug "$BRANCH_NAME")-$REVIEW_MODE"' "large planner run dir must be timestamp-branch-mode only"
require_literal "$ROOT_DIR/scripts/phase11-plan-file-batches.sh" 'RUN_ID="$RUN_TIMESTAMP-$(branch_slug "$BRANCH_NAME")-$REVIEW_MODE"' "file planner run dir must be timestamp-branch-mode only"
require_literal "$SKILL_FILE" '`RUN_DIR` 目录名固定为 `{YYYYMMDD-HHMMSS}-{branch_slug}-{REVIEW_MODE}`' "skill contract must document concise run directory naming"
require_literal "$SKILL_FILE" '审查范围、分批策略和任务类型必须从 `plan.json` 读取' "scope and strategy must live in plan.json instead of run dir name"
if grep -q 'RUN_ID=.*large-maven\|RUN_ID=.*file-batches\|RUN_SCOPE_SLUG\|RUN_STRATEGY_SLUG' "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" "$ROOT_DIR/scripts/phase11-plan-file-batches.sh"; then
  echo "run directory name must not include scope, strategy, or batch-type suffixes" >&2
  exit 1
fi
grep -q "自行输入批次号" "$SKILL_FILE"
grep -q "BATCH_SELECTION" "$SKILL_FILE"
grep -q "RUN_BATCH_IDS" "$SKILL_FILE"
grep -q "RUN_BATCH_COUNT" "$SKILL_FILE"
if grep -q '分批并行扫描（{BATCH_COUNT} 批 / {CONCURRENCY} 路并发）' "$SKILL_FILE"; then
  echo "large repo execution copy must distinguish current-run batch count from total batch count" >&2
  exit 1
fi

# Skill must have batch agent orchestration
grep -q "分批并行模式" "$SKILL_FILE"
grep -q "BATCH_FILE_COUNT" "$SKILL_FILE"
grep -q "BATCH_LINE_COUNT" "$SKILL_FILE"
grep -q "飞书保存不可用" "$SKILL_FILE"

# Skill must have report merging
grep -q "报告合并" "$SKILL_FILE"
grep -q "跨批去重" "$SKILL_FILE"
grep -q "聚合同类问题" "$SKILL_FILE"

# Skill batch mode only for stock review
grep -q "仅对存量审查生效" "$SKILL_FILE"

# Skill must show batch info in step 7 execution plan
grep -q "扫描策略" "$SKILL_FILE"
grep -q "分批并行扫描" "$SKILL_FILE"

# === AGENTS.md / CLAUDE.md 同步守卫 ===
# 这两个文件服务不同工具（Codex / Claude Code），除以下两处预期差异外，正文必须逐行一致，
# 防止架构描述在两份拷贝间漂移：
#   - 第 1 行：标题（# AGENTS.md / # CLAUDE.md）
#   - 第 3 行：首句工具引导语（含工具名和域名，Codex.ai/code vs claude.ai/code）
# 第 7 行的 "claudecode" vs "Claude Code" 通过归一化为同一写法后参与比较。
sync_normalize() {
  local file="$1"
  perl -CS -Mutf8 -ne '
    next if $. == 1 || $. == 3;          # 跳过第 1 行标题、第 3 行首句工具引导语
    s/\bclaudecode\b/Claude Code/g;       # 统一第 7 行的工具名写法
    print;
  ' "$file"
}

SYNC_DIFF="$(diff <(sync_normalize "$AGENTS_FILE") <(sync_normalize "$CLAUDE_FILE") || true)"
if [ -n "$SYNC_DIFF" ]; then
  echo "AGENTS.md 与 CLAUDE.md 正文不同步（标题行与首句工具引导语的差异已排除）。请同步两文件后再次运行。" >&2
  echo "差异如下：" >&2
  echo "$SYNC_DIFF" >&2
  echo "提示：修改时请同时编辑 AGENTS.md 和 CLAUDE.md；仅第 1 行标题和第 3 行首句允许不同。" >&2
  exit 1
fi

# === 前端多语言文档同步断言 ===
for f in \
  "scripts/core/detect-language.sh" \
  "scripts/core/validate-scope.sh" \
  "scripts/core/plan-file-batches.sh" \
  "scripts/core/merge-batch-results.sh" \
  "scripts/core/show-batch-status.sh" \
  "scripts/languages/frontend/detect-project.sh" \
  "scripts/languages/frontend/scan-project.sh" \
  "scripts/languages/frontend/collect-source-files.sh" \
  "scripts/languages/frontend/detect-code-intelligence.sh" \
  "agents/cc-code-reviewer-frontend.md" \
  "references/language-adapter-contract.md" \
  "references/languages/java/review-framework.md" \
  "references/languages/frontend/source-scope.md" \
  "references/languages/frontend/review-framework.md" \
  "references/languages/frontend/react-rules.md"; do
  [ -f "$ROOT_DIR/$f" ] || { echo "MISSING: $f" >&2; exit 1; }
done

# shared-review-framework.md 必须已删除（过度设计，不再维护公共维度分类法）
if [ -f "$ROOT_DIR/references/shared-review-framework.md" ]; then
  echo "FAIL: shared-review-framework.md 应已删除，审查框架各语言独立" >&2
  exit 1
fi

# 前端审查框架必须使用独立维度集，不得引用 Java 公共维度 ID（D01_CORRECTNESS 等）
FE_FRAMEWORK="$ROOT_DIR/references/languages/frontend/review-framework.md"
if grep -qE 'D(0[1-9]|1[0-5])_[A-Z_]+' "$FE_FRAMEWORK"; then
  echo "FAIL: 前端框架不得引用 Java 公共维度 ID" >&2
  exit 1
fi
# 正向断言：必须包含类型安全维度（中后台 P0 级）
grep -q "类型安全" "$FE_FRAMEWORK" || { echo "FAIL: 前端框架必须包含类型安全维度" >&2; exit 1; }
# 正向断言：必须声明 11 维度（硬断言，防止再次注水膨胀）
FE_DIM_COUNT=$(grep -cE '^### [0-9]+\. ' "$FE_FRAMEWORK")
if [ "$FE_DIM_COUNT" -ne 11 ]; then
  echo "FAIL: 前端框架必须声明 11 维度，当前 $FE_DIM_COUNT" >&2
  exit 1
fi

# SKILL.md 必须含语言路由分支
grep -q "语言探测与路由" "$SKILL_FILE"
grep -q "CANDIDATE_LANGUAGE:frontend" "$SKILL_FILE"
grep -q "cc-code-reviewer-frontend" "$SKILL_FILE"
# 前端 agent 必须被实际 dispatch（subagent_type 按 LANGUAGE_ID 选择，不能只硬编码 Java agent）
grep -q 'cc-code-reviewer:cc-code-reviewer-frontend' "$SKILL_FILE"
# 前端 agent 在 dispatch 点必须按 LANGUAGE_ID 条件化（至少出现 2 次）
FRONTEND_DISPATCH_COUNT="$(grep -c 'cc-code-reviewer:cc-code-reviewer-frontend' "$SKILL_FILE")"
test "$FRONTEND_DISPATCH_COUNT" -ge 2

# SKILL.md 路径准备必须按 LANGUAGE_ID 分支，前端注入三个专属路径（不能写死 Java 路径）
grep -q 'LANGUAGE_ID.*frontend' "$SKILL_FILE"
grep -q 'REACT_RULES_PATH' "$SKILL_FILE"
grep -q 'SOURCE_SCOPE_PATH' "$SKILL_FILE"
grep -q 'references/languages/frontend/review-framework.md' "$SKILL_FILE"
grep -q 'references/languages/frontend/react-rules.md' "$SKILL_FILE"
grep -q 'references/languages/frontend/source-scope.md' "$SKILL_FILE"

# 前端 agent 必须期望前端专属路径（不能只依赖 Java 的 REVIEW_FRAMEWORK_PATH）
grep -q "前端审查框架路径" "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"
grep -q "React 规则路径" "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"
grep -q "源码范围路径" "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"

# 前端 agent 不得残留旧 15 维度编号（D01-D15）或维度 12-15 引用
if grep -qE 'D(0[1-9]|1[0-5])[^0-9]|维度 ?1[2345]|1-15|15 维度' "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"; then
  echo "FAIL: 前端 agent 残留旧 15 维度编号或维度 12-15 引用" >&2
  exit 1
fi

# 前端矩阵与 React 规则必须被前端 Agent 引用
grep -q "review-framework" "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"
grep -q "react-rules" "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"

echo "✅ 契约文档测试通过"
