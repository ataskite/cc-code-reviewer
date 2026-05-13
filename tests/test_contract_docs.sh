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

grep -q "项目/技术栈扫描" "$README_FILE"
grep -q "快速启动支持.*--key=value" "$README_FILE"
grep -q "code-review-report-{PROJECT_NAME}-{YYYYMMDD-HHmmss}.md" "$README_FILE"
grep -q "phase5-preview-recent-commits" "$README_FILE"
grep -q "phase5-prepare-incremental" "$README_FILE"
grep -q "/cc-code-reviewer:cc-code-fixer" "$README_FILE"
grep -q "修复阶段" "$README_FILE"
grep -q "worktree" "$README_FILE"
grep -q "fix-report-{PROJECT_NAME}-{YYYYMMDD-HHmmss}.md" "$README_FILE"
grep -q "待修复问题确认清单" "$README_FILE"
grep -q "修复阶段必须交互确认" "$README_FILE"
grep -q "工作区策略交给 Superpowers" "$README_FILE"
grep -q "subagent-driven-development" "$README_FILE"
grep -q "docs/assets/architecture-overview.png" "$README_FILE"
if grep -qE "FixAgent|agents/cc-code-fixer|模型 / effort|MODEL_PREFERENCE|EFFORT_PREFERENCE" "$README_FILE"; then
  echo "README fix flow must not reference removed fixer agent or model/effort selection" >&2
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
test -f "$ARCHITECTURE_SVG"
grep -q "问题清单位置" "$ARCHITECTURE_SVG"
grep -q "Superpowers" "$ARCHITECTURE_SVG"
grep -q "subagent-driven-development" "$ARCHITECTURE_SVG"
if grep -qE "Fix Agent|agents/cc-code-fixer|模型 / effort|MODEL_PREFERENCE|EFFORT_PREFERENCE" "$ARCHITECTURE_SVG"; then
  echo "architecture overview image source must match current Superpowers-based fixer architecture" >&2
  exit 1
fi

grep -q "🧩 技术栈扫描" "$EXAMPLES_FILE"
grep -q "飞书上传不可用" "$EXAMPLES_FILE"
grep -q "已识别参数" "$EXAMPLES_FILE"
grep -q "报告已保存到" "$EXAMPLES_FILE"

grep -qx "# Fix Workflow" "$FIX_WORKFLOW_FILE"
grep -qx "## Fix Input Normalization" "$FIX_WORKFLOW_FILE"
grep -qx "## Preflight Sequence" "$FIX_WORKFLOW_FILE"
grep -qx "## Superpowers Flow" "$FIX_WORKFLOW_FILE"
grep -qx "## Degraded Mode" "$FIX_WORKFLOW_FILE"
grep -qx "## Fix Scope Rules" "$FIX_WORKFLOW_FILE"
grep -qx "## Workspace Rules" "$FIX_WORKFLOW_FILE"
grep -q "brainstorming" "$FIX_WORKFLOW_FILE"
grep -q "test-driven-development" "$FIX_WORKFLOW_FILE"
grep -q "verification-before-completion" "$FIX_WORKFLOW_FILE"
grep -q "交互确认是硬门禁" "$FIX_WORKFLOW_FILE"
grep -q "工作区策略交给 Superpowers" "$FIX_WORKFLOW_FILE"
grep -q "subagent-driven-development" "$FIX_WORKFLOW_FILE"
grep -q "无已归一化问题上下文时必须停止修复" "$FIX_WORKFLOW_FILE" "$FIX_FEISHU_FILE"
grep -q "Other/free-form 中粘贴" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"
grep -q "本地 Markdown 必须直接读取文件内容" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE"
grep -q "不得使用 Python 脚本读取飞书云文档或飞书多维表格" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_FEISHU_FILE"
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
grep -q "工作区策略交给 Superpowers" "$FIX_SKILL_FILE"
grep -q "确认执行计划" "$FIX_SKILL_FILE"
grep -q "brainstorming" "$FIX_SKILL_FILE"
grep -q "subagent-driven-development" "$FIX_SKILL_FILE"
if grep -qE 'FAST_MODE|FAST_PARAMS|快速启动|`--scope`|`--workspace`|`--strategy`|修复策略|请选择本次修复使用的工作区策略' "$FIX_SKILL_FILE"; then
  echo "cc-code-fixer must not contain fast mode, workspace strategy, or repair strategy selection" >&2
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
[ "$PLUGIN_VERSION" = "1.1.5" ]
grep -q "code-fixer" "$PLUGIN_FILE"
grep -q '"code-fix"' "$PLUGIN_FILE"
grep -q '"code-fix"' "$MARKETPLACE_FILE"
grep -q "report-driven fixing" "$MARKETPLACE_FILE"
