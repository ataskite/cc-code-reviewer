#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_FILE="$ROOT_DIR/agents/cc-code-reviewer.md"
FEISHU_FILE="$ROOT_DIR/references/feishu-integration.md"
SKILL_FILE="$ROOT_DIR/skills/cc-code-reviewer/SKILL.md"
README_FILE="$ROOT_DIR/README.md"
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

grep -q "### 第三步之后：持久化报告文件" "$AGENT_FILE"
grep -q "REPORT_FILENAME" "$AGENT_FILE"
grep -q "所有上传和本地输出都必须复用同一个 Markdown 文件" "$AGENT_FILE"

if grep -q 'field-create .*"name":"备注","type":"text"' "$FEISHU_FILE"; then
  echo "默认主字段会重命名为备注，不应再创建重复的备注字段" >&2
  exit 1
fi

grep -q 'field-update .*"name":"备注","type":"text"' "$FEISHU_FILE"
grep -q "共 17 个字段" "$FEISHU_FILE"
grep -q "基础字段（14 个）" "$README_FILE"
if grep -q "负责人" "$FEISHU_FILE" "$README_FILE"; then
  echo "scan-stage Feishu Base schema must not include 负责人" >&2
  exit 1
fi

grep -q "### 第一步之后：提取项目路径与快速启动参数" "$SKILL_FILE"
grep -q "优先提取 Git URL" "$SKILL_FILE"
grep -q "必须一次性解析完整参数表" "$SKILL_FILE"
grep -q "缺少必填参数" "$SKILL_FILE"
grep -q "非法参数值" "$SKILL_FILE"
grep -q "禁止降级为交互式模式" "$SKILL_FILE"

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
grep -q 'REVIEW_FRAMEWORK_PATH=.*references/review-framework.md' "$SKILL_FILE"
grep -q 'REPORT_FORMAT_PATH=.*references/report-format.md' "$SKILL_FILE"
GLOBAL_REFERENCE_LINE="$(grep -n "### 第五步之前：准备审查参考文件路径" "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
TASK_LAUNCH_LINE="$(grep -n "### 第五步：调用子 agent 执行代码审查" "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
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

grep -q "项目/技术栈扫描" "$README_FILE"
grep -q "扫描 → 人工确认 → 修复 → 验证 → 报告/写回" "$README_FILE"
grep -q "## 产品定位" "$README_FILE"
grep -q "## 核心能力" "$README_FILE"
grep -q "端到端闭环" "$README_FILE"
grep -q "快速启动支持.*--key=value" "$README_FILE"
grep -q "code-review-report-{PROJECT_NAME}-{YYYYMMDD-HHmmss}.md" "$README_FILE"
grep -q "/cc-code-reviewer:cc-code-fixer" "$README_FILE"
grep -q "修复阶段" "$README_FILE"
grep -q "worktree" "$README_FILE"
grep -q "fix-report-{PROJECT_NAME}-{YYYYMMDD-HHmmss}.md" "$README_FILE"
grep -q "待修复问题确认清单" "$README_FILE"
grep -q "修复阶段必须交互确认" "$README_FILE"
grep -q "Superpowers 可选" "$README_FILE"
grep -q "直接修复" "$README_FILE"
grep -q "subagent-driven-development" "$README_FILE"
grep -q "写回原始本地 Markdown" "$README_FILE"
grep -q "写回原始飞书云文档" "$README_FILE"
grep -q "写回原始飞书多维表格" "$README_FILE"
grep -q "创建独立本地 Markdown 修复报告" "$README_FILE"
grep -q "创建独立飞书云文档修复报告" "$README_FILE"
grep -q "创建独立飞书多维表格修复报告" "$README_FILE"
grep -q "技术栈识别与审查维度动态匹配" "$README_FILE"
grep -q "15 个维度是基础框架" "$README_FILE"
grep -q "Scan 不修改业务代码，Fix 不重新执行完整审查" "$README_FILE"
grep -q "项目级 ignore" "$README_FILE"
grep -q "/cc-code-reviewer:cc-code-ignore" "$README_FILE"
grep -q "当前 Git 用户" "$README_FILE"
grep -q "## Harness 架构设计" "$README_FILE"
grep -q "整体 Harness 架构图" "$README_FILE"
grep -q "入口层：User / Claude Code" "$README_FILE"
grep -q "Scan Harness：发现候选问题" "$README_FILE"
grep -q "人工确认层：从候选问题到 Fix TODO List" "$README_FILE"
grep -q "Fix Harness：确认后分支执行" "$README_FILE"
grep -q "修复执行层：直接修复 / Superpowers 修复" "$README_FILE"
grep -q "Integration 层：lark-cli 可选平台读写能力" "$README_FILE"
grep -q "Harness 边界" "$README_FILE"
grep -q "phase9-collect-fix-metadata" "$FIX_SKILL_FILE" "$FIX_WORKFLOW_FILE" "$FIX_REPORT_FILE"
grep -q "docs/assets/architecture-overview.png" "$README_FILE"
if grep -qE "## (脚本说明|测试|开发与维护)" "$README_FILE"; then
  echo "README should not include script, testing, or development-maintenance sections" >&2
  exit 1
fi
if grep -qE "phase[0-9]-|scripts/|tests/run_all.sh" "$README_FILE"; then
  echo "README should not expose internal script/test details" >&2
  exit 1
fi
if grep -qE "FixAgent|agents/cc-code-fixer|模型 / effort|MODEL_PREFERENCE|EFFORT_PREFERENCE" "$README_FILE"; then
  echo "README fix flow must not reference removed fixer agent or model/effort selection" >&2
  exit 1
fi
if grep -q "创建飞书云文档或回写多维表格" "$README_FILE"; then
  echo "README fix flow must describe dynamic output targets, not the old cloud-doc/base-only output" >&2
  exit 1
fi
if grep -q "/cc-code-reviewer:cc-code-fixer .*--scope" "$README_FILE"; then
  echo "README fixer examples must not use --scope fast-style parameters" >&2
  exit 1
fi
if grep -q "/cc-code-reviewer:cc-code-fixer .*--mode" "$README_FILE"; then
  echo "README fixer examples must not use unsupported --mode" >&2
  exit 1
fi
test -f "$ARCHITECTURE_PNG"
if [ -f "$ARCHITECTURE_SVG" ]; then
  echo "architecture overview is imagegen PNG-only; SVG source should not be kept" >&2
  exit 1
fi

grep -q "🧩 技术栈扫描" "$EXAMPLES_FILE"
grep -q "飞书上传不可用" "$EXAMPLES_FILE"
grep -q "已识别参数" "$EXAMPLES_FILE"
grep -q "报告已保存到" "$EXAMPLES_FILE"
grep -q "项目 ignore 命中" "$EXAMPLES_FILE"

test -f "$IGNORE_SKILL_FILE"
test -f "$IGNORE_WORKFLOW_FILE"
grep -q "AI 指令型 ignore 文件" "$IGNORE_SKILL_FILE" "$IGNORE_WORKFLOW_FILE"
grep -q ".cc-code-reviewer/ignore/issues.yml" "$IGNORE_SKILL_FILE" "$IGNORE_WORKFLOW_FILE" "$SKILL_FILE" "$AGENT_FILE" "$README_FILE"
grep -q "不存报告编号" "$IGNORE_SKILL_FILE" "$IGNORE_WORKFLOW_FILE"
grep -q "name:" "$IGNORE_WORKFLOW_FILE"
grep -q "applies_to:" "$IGNORE_WORKFLOW_FILE"
grep -q "skip_when:" "$IGNORE_WORKFLOW_FILE"
grep -q "飞书 Base" "$IGNORE_SKILL_FILE" "$IGNORE_WORKFLOW_FILE"
grep -q "本地 Markdown" "$IGNORE_SKILL_FILE" "$IGNORE_WORKFLOW_FILE"
grep -q "用户指定问题编号" "$IGNORE_SKILL_FILE" "$IGNORE_WORKFLOW_FILE"

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
grep -q "明确标注为已修复、已忽略或不适用" "$README_FILE"
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
if grep -q "快速启动" "$FIX_WORKFLOW_FILE"; then
  echo "fix workflow must not mention fast mode" >&2
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
if grep -q "快速启动" "$FIX_EXAMPLES_FILE"; then
  echo "fix examples must not document fast mode" >&2
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
if grep -qE 'FAST_MODE|FAST_PARAMS|快速启动|`--scope`|`--workspace`|`--strategy`' "$FIX_SKILL_FILE"; then
  echo "cc-code-fixer must not contain fast mode or fast-style parameters" >&2
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
MARKETPLACE_PLUGIN_VERSION="$(grep -E '"version":' "$MARKETPLACE_FILE" | sed -n '2p' | sed 's/.*"version": *"\([^"]*\)".*/\1/')"
[ "$PLUGIN_VERSION" = "$MARKETPLACE_VERSION" ]
[ "$PLUGIN_VERSION" = "$MARKETPLACE_PLUGIN_VERSION" ]
[ "$PLUGIN_VERSION" = "1.2.0" ]
grep -q "code-fixer" "$PLUGIN_FILE"
grep -q '"code-fix"' "$PLUGIN_FILE"
grep -q '"code-fix"' "$MARKETPLACE_FILE"
grep -q "report-driven fixing" "$MARKETPLACE_FILE"

# === Batch scanning contracts ===

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

# Skill must have concurrency step
grep -q "选择并发数" "$SKILL_FILE"
grep -q "CONCURRENCY" "$SKILL_FILE"
grep -q "串行执行" "$SKILL_FILE"
grep -q "3 路并发" "$SKILL_FILE"
grep -q "5 路并发" "$SKILL_FILE"

# Skill must have batch agent orchestration
grep -q "分批并行模式" "$SKILL_FILE"
grep -q "BATCH_FILE_COUNT" "$SKILL_FILE"
grep -q "BATCH_LINE_COUNT" "$SKILL_FILE"
grep -q "飞书上传不可用" "$SKILL_FILE"

# Skill must have report merging
grep -q "报告合并" "$SKILL_FILE"
grep -q "跨批去重" "$SKILL_FILE"
grep -q "聚合同类问题" "$SKILL_FILE"

# Skill must have --concurrency fast mode parameter
grep -q "\-\-concurrency" "$SKILL_FILE"

# Skill batch mode only for stock review
grep -q "仅对存量审查生效" "$SKILL_FILE"

# Skill must show batch info in step 7 execution plan
grep -q "扫描策略" "$SKILL_FILE"
grep -q "分批并行扫描" "$SKILL_FILE"
