#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_FILE="$ROOT_DIR/agents/cc-code-reviewer.md"
FEISHU_FILE="$ROOT_DIR/references/feishu-integration.md"

grep -Fq '必须优先按 `lark-doc` skill 执行云文档创建' "$AGENT_FILE" "$FEISHU_FILE"
grep -Fq '必须优先按 `lark-base` skill 执行多维表格创建和写入' "$AGENT_FILE" "$FEISHU_FILE"
grep -Fq 'lark-cli docs +create' "$FEISHU_FILE"
grep -Fq -- '--api-version v2' "$FEISHU_FILE"
grep -Fq -- '--doc-format markdown' "$FEISHU_FILE"
grep -Fq -- '--content @' "$FEISHU_FILE"
grep -Fq '先 `cd` 到报告文件所在目录' "$FEISHU_FILE"
grep -Fq '上传前必须校验 Markdown 文件第一条非空内容是一级标题' "$AGENT_FILE" "$FEISHU_FILE"
grep -Fq '合并报告必须使用 `summary.json` 中的 `report_title` 校验标题' "$AGENT_FILE" "$FEISHU_FILE"
grep -Fq '不得上传会在飞书显示为 `untitled` 的无标题内容' "$AGENT_FILE" "$FEISHU_FILE"

grep -Fq '不得调用 `lark-cli doc create`' "$AGENT_FILE" "$FEISHU_FILE"
grep -Fq '不得调用 `lark-cli docs create`' "$AGENT_FILE" "$FEISHU_FILE"
grep -Fq '不得使用 `--content-file`' "$AGENT_FILE" "$FEISHU_FILE"
grep -Fq '不得使用 `--markdown`' "$AGENT_FILE" "$FEISHU_FILE"
