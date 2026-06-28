#!/bin/bash
# 测试：phase11-plan-file-batches.sh 委托 core/plan-file-batches.sh
# 验证：生成的 plan.json 含 language_id=java（证明走了 core/ 版本，而非旧 Java 内联实现）
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
mkdir -p "$TMP/src/main/java/com/example"
echo "public class A {}" > "$TMP/src/main/java/com/example/A.java"

OUT="$(CC_REVIEW_CONTEXT_SCALE=1 bash "$ROOT_DIR/scripts/languages/java/plan-file-batches.sh" "$TMP" standard main 2>&1)"
RUN_DIR="$(printf '%s\n' "$OUT" | sed -n 's/^RUN_DIR=//p')"
[ -n "$RUN_DIR" ] || { echo "FAIL: 未输出 RUN_DIR" >&2; echo "$OUT" >&2; exit 1; }
PLAN_PATH="$RUN_DIR/plan.json"
[ -f "$PLAN_PATH" ] || { echo "FAIL: plan.json 未生成" >&2; exit 1; }
# core 版本写 language_id；瘦身后 plan.json 应同时含 language_id=java 和 java_* 别名
grep -q '"language_id":"java"' "$PLAN_PATH" || \
  grep -q '"language_id": "java"' "$PLAN_PATH" || \
  { echo "FAIL: Java 文件分批应通过 core/ 走，plan.json 须含 language_id=java" >&2; cat "$PLAN_PATH" >&2; exit 1; }
rm -rf "$TMP"
echo "PASS: java plan-file-batches uses core"
