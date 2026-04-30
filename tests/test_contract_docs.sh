#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_FILE="$ROOT_DIR/agents/cc-code-reviewer.md"
FEISHU_FILE="$ROOT_DIR/references/feishu-integration.md"
SKILL_FILE="$ROOT_DIR/skills/cc-code-reviewer/SKILL.md"

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
