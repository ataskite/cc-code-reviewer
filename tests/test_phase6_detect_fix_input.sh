#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase6 fix input.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

REPORT_FILE="$TMP_DIR/code-review-report-demo-20260507-103000.md"
cat >"$REPORT_FILE" <<'REPORT'
# Java 代码审查报告

**问题编号**：P0-1
**位置**：src/main/java/demo/UserController.java:42
**置信度**：高 | **所属维度**：安全
**问题**：接口缺少鉴权
REPORT

LOCAL_OUTPUT="$(bash "$ROOT_DIR/scripts/core/detect-fix-input.sh" "$REPORT_FILE")"
echo "$LOCAL_OUTPUT" | grep -Fq "FIX_INPUT_TYPE=local-markdown"
echo "$LOCAL_OUTPUT" | grep -Fq "FIX_INPUT_PATH=$REPORT_FILE"
echo "$LOCAL_OUTPUT" | grep -Fq "FIX_INPUT_EXISTS=true"

DOC_OUTPUT="$TMP_DIR/phase6-doc.out"
if bash "$ROOT_DIR/scripts/core/detect-fix-input.sh" "https://example.feishu.cn/docx/ABC123" >"$DOC_OUTPUT" 2>&1; then
  echo "phase6 must not handle Feishu doc inputs" >&2
  exit 1
fi
grep -Fq "飞书云文档和飞书多维表格输入不得调用 phase6-detect-fix-input.sh" "$DOC_OUTPUT"

BASE_OUTPUT="$TMP_DIR/phase6-base.out"
if bash "$ROOT_DIR/scripts/core/detect-fix-input.sh" "https://example.feishu.cn/base/BASE123?table=tbl456" >"$BASE_OUTPUT" 2>&1; then
  echo "phase6 must not handle Feishu base inputs" >&2
  exit 1
fi
grep -Fq "飞书云文档和飞书多维表格输入不得调用 phase6-detect-fix-input.sh" "$BASE_OUTPUT"

WIKI_BASE_URL="https://example.feishu.cn/wiki/FlKdwsFpIih3CzkQhl7cwR40nsz?table=tblhnVIjMA4Rts1i&view=vewiXLBlKx"
WIKI_BASE_OUTPUT="$TMP_DIR/phase6-wiki-base.out"
if bash "$ROOT_DIR/scripts/core/detect-fix-input.sh" "$WIKI_BASE_URL" >"$WIKI_BASE_OUTPUT" 2>&1; then
  echo "phase6 must not handle Feishu wiki base inputs" >&2
  exit 1
fi
grep -Fq "飞书云文档和飞书多维表格输入不得调用 phase6-detect-fix-input.sh" "$WIKI_BASE_OUTPUT"

TOKEN_OUTPUT="$TMP_DIR/phase6-base-token.out"
if bash "$ROOT_DIR/scripts/core/detect-fix-input.sh" "base:BASE123:tbl456" >"$TOKEN_OUTPUT" 2>&1; then
  echo "phase6 must not handle Feishu base token inputs" >&2
  exit 1
fi
grep -Fq "飞书云文档和飞书多维表格输入不得调用 phase6-detect-fix-input.sh" "$TOKEN_OUTPUT"

MISSING_OUTPUT="$TMP_DIR/phase6-missing.out"
if bash "$ROOT_DIR/scripts/core/detect-fix-input.sh" "$TMP_DIR/missing.md" >"$MISSING_OUTPUT" 2>&1; then
  echo "phase6 should fail for missing local markdown" >&2
  exit 1
fi
grep -Fq "修复输入不存在" "$MISSING_OUTPUT"

UNSUPPORTED_OUTPUT="$TMP_DIR/phase6-unsupported.out"
if bash "$ROOT_DIR/scripts/core/detect-fix-input.sh" "not-a-report-source" >"$UNSUPPORTED_OUTPUT" 2>&1; then
  echo "phase6 should fail for unsupported source" >&2
  exit 1
fi
grep -Fq "无法识别修复输入来源" "$UNSUPPORTED_OUTPUT"

NEWLINE_OUTPUT="$TMP_DIR/phase6-newline.out"
if bash "$ROOT_DIR/scripts/core/detect-fix-input.sh" $'https://example.feishu.cn/docx/ABC123\nFIX_INPUT_TYPE=local-markdown' >"$NEWLINE_OUTPUT" 2>&1; then
  echo "phase6 should fail for newline input" >&2
  exit 1
fi
grep -Fq "修复输入不能包含换行符" "$NEWLINE_OUTPUT"

CR_OUTPUT="$TMP_DIR/phase6-cr.out"
if bash "$ROOT_DIR/scripts/core/detect-fix-input.sh" $'base:BASE123:tbl456\rFEISHU_TABLE_ID=other' >"$CR_OUTPUT" 2>&1; then
  echo "phase6 should fail for carriage return input" >&2
  exit 1
fi
grep -Fq "修复输入不能包含换行符" "$CR_OUTPUT"
