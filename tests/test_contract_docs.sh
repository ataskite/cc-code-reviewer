#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_FILE="$ROOT_DIR/agents/cc-code-reviewer.md"
FEISHU_FILE="$ROOT_DIR/references/feishu-integration.md"
SKILL_FILE="$ROOT_DIR/skills/cc-code-reviewer/SKILL.md"
README_FILE="$ROOT_DIR/README.md"
EXAMPLES_FILE="$ROOT_DIR/references/examples.md"
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

grep -q "项目/技术栈扫描" "$README_FILE"
grep -q "快速启动支持.*--key=value" "$README_FILE"
grep -q "code-review-report-{PROJECT_NAME}-{YYYYMMDD-HHmmss}.md" "$README_FILE"
grep -q "phase5-prepare-incremental" "$README_FILE"

grep -q "🧩 技术栈扫描" "$EXAMPLES_FILE"
grep -q "飞书上传不可用" "$EXAMPLES_FILE"
grep -q "已识别参数" "$EXAMPLES_FILE"
grep -q "报告已保存到" "$EXAMPLES_FILE"

PLUGIN_VERSION="$(grep -E '"version":' "$PLUGIN_FILE" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')"
MARKETPLACE_VERSION="$(grep -E '"version":' "$MARKETPLACE_FILE" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')"
[ "$PLUGIN_VERSION" = "$MARKETPLACE_VERSION" ]
