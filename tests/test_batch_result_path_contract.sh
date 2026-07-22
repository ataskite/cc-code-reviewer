#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_FILE="$ROOT_DIR/agents/cc-code-reviewer.md"
SKILL_FILE="$ROOT_DIR/skills/cc-code-reviewer/SKILL.md"
EXAMPLES_FILE="$ROOT_DIR/references/examples.md"

grep -Fq '大型仓库批次模式不得自行命名结果文件' "$AGENT_FILE"
grep -Fq '必须把批次发现清单写入 `BATCH_RESULT_PATH`' "$AGENT_FILE"
grep -Fq '不得写入 `*.result.md`' "$AGENT_FILE"
grep -Fq '状态文件中的 `result_path` 必须指向同一个 `BATCH_RESULT_PATH`' "$AGENT_FILE"
grep -Fq 'file-token-batching 计划必须使用其 `batch_file_list` 对应的 `BATCH_FILE_LIST`' "$AGENT_FILE"
grep -Fq '两种模式都必须写入 `BATCH_RESULT_PATH`，不使用 `/tmp/review-batch-*`' "$AGENT_FILE"

grep -Fq "每批完成后写入 BATCH_RESULT_PATH（对应 results/batch-XXX.md）" "$EXAMPLES_FILE"
grep -Fq "批次结果文件 | {BATCH_RESULT_PATH}（对应 RUN_DIR/results/batch-XXX.md）" "$SKILL_FILE"
