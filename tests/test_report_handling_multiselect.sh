#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_FILE="$ROOT_DIR/skills/cc-code-reviewer/SKILL.md"
AGENT_FILE="$ROOT_DIR/agents/cc-code-reviewer.md"
FEISHU_FILE="$ROOT_DIR/references/feishu-integration.md"
EXAMPLES_FILE="$ROOT_DIR/references/examples.md"

UPLOAD_PICK_LINE="$(grep -n 'question: "请选择审查报告的保存方式"' "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
if [ -z "$UPLOAD_PICK_LINE" ]; then
  echo "missing report handling question" >&2
  exit 1
fi

UPLOAD_MULTISELECT_BLOCK="$(sed -n "${UPLOAD_PICK_LINE},$((UPLOAD_PICK_LINE + 18))p" "$SKILL_FILE")"
if ! printf '%s\n' "$UPLOAD_MULTISELECT_BLOCK" | grep -q -- "- multiSelect: true"; then
  echo "report handling INTERACT must be multi-select" >&2
  exit 1
fi

if printf '%s\n' "$UPLOAD_MULTISELECT_BLOCK" | grep -q "同时上传两者"; then
  echo "report handling choices must not include the old combined upload option" >&2
  exit 1
fi

grep -Fq "报告保存方式为多选" "$SKILL_FILE"
grep -Fq "用户可选择本地 Markdown 报告、飞书云文档和飞书多维表格中的任意一个或多个，支持任意组合多选" "$SKILL_FILE"

if grep -q "同时上传两者" "$SKILL_FILE" "$AGENT_FILE" "$FEISHU_FILE" "$EXAMPLES_FILE"; then
  echo "report handling must remove the old combined upload option" >&2
  exit 1
fi
