#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_FILE="$ROOT_DIR/agents/cc-code-reviewer.md"
FE_AGENT_FILE="$ROOT_DIR/agents/cc-code-reviewer-frontend.md"
FEISHU_FILE="$ROOT_DIR/references/feishu-integration.md"

# 飞书操作规范措辞只约束主 skill 的参考文档（feishu-integration.md）；
# 子代理不再执行飞书上传，不包含这些操作措辞。

grep -Fq '必须优先按 `lark-doc` skill 执行云文档创建' "$FEISHU_FILE"
grep -Fq '必须优先按 `lark-base` skill 执行多维表格创建和写入' "$FEISHU_FILE"
grep -Fq 'lark-cli docs +create' "$FEISHU_FILE"
grep -Fq -- '--api-version v2' "$FEISHU_FILE"
grep -Fq -- '--doc-format markdown' "$FEISHU_FILE"
grep -Fq -- '--content @' "$FEISHU_FILE"
grep -Fq '先 `cd` 到报告文件所在目录' "$FEISHU_FILE"
grep -Fq '上传前必须校验 Markdown 文件第一条非空内容是一级标题' "$FEISHU_FILE"
grep -Fq '合并报告必须使用 `summary.json` 中的 `report_title` 校验标题' "$FEISHU_FILE"
grep -Fq '不得上传会在飞书显示为 `untitled` 的无标题内容' "$FEISHU_FILE"

grep -Fq '不得调用 `lark-cli doc create`' "$FEISHU_FILE"
grep -Fq '不得调用 `lark-cli docs create`' "$FEISHU_FILE"
grep -Fq '不得使用 `--content-file`' "$FEISHU_FILE"
grep -Fq '不得使用 `--markdown`' "$FEISHU_FILE"

# 子代理必须明确声明不执行飞书上传（职责迁移后的新契约）
grep -Fq '不执行飞书上传' "$AGENT_FILE"
grep -Fq '不执行飞书上传' "$FE_AGENT_FILE"
