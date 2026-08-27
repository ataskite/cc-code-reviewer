#!/bin/bash
# 测试：languages/java/plan-file-batches.sh 委托 core/plan-file-batches.sh
# 验证：生成的 plan.json 含 language_id=java（证明走了 core/ 版本，而非旧 Java 内联实现）
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
mkdir -p "$TMP/src/main/java/com/example"
echo "public class A {}" > "$TMP/src/main/java/com/example/A.java"

OUT="$(bash "$ROOT_DIR/scripts/languages/java/plan-file-batches.sh" "$TMP" standard main 2>&1)"
RUN_DIR="$(printf '%s\n' "$OUT" | sed -n 's/^RUN_DIR=//p')"
[ -n "$RUN_DIR" ] || { echo "FAIL: 未输出 RUN_DIR" >&2; echo "$OUT" >&2; exit 1; }
PLAN_PATH="$RUN_DIR/plan.json"
[ -f "$PLAN_PATH" ] || { echo "FAIL: plan.json 未生成" >&2; exit 1; }
# core 版本写 language_id；瘦身后 plan.json 应同时含 language_id=java 和 java_* 别名
grep -q '"language_id":"java"' "$PLAN_PATH" || \
  grep -q '"language_id": "java"' "$PLAN_PATH" || \
  { echo "FAIL: Java 文件分批应通过 core/ 走，plan.json 须含 language_id=java" >&2; cat "$PLAN_PATH" >&2; exit 1; }

# 语义分组 env 透传：适配器须把 CC_CODE_REVIEWER_SEMANTIC_GROUPS_FILE 原样传给 core。
# 单文件 A.java 登记为 grp-a（仓库相对路径）→ plan.json 披露 semantic_grouping_enabled，
# batch-001.json 披露 semantic_group_ids。
GROUPS_FILE="$TMP/semantic-groups.tsv"
printf 'grp-a\tsrc/main/java/com/example/A.java\n' > "$GROUPS_FILE"
OUT2="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260826-060000 \
        CC_CODE_REVIEWER_SEMANTIC_GROUPS_FILE="$GROUPS_FILE" \
        bash "$ROOT_DIR/scripts/languages/java/plan-file-batches.sh" "$TMP" standard main 2>&1)"
RUN_DIR2="$(printf '%s\n' "$OUT2" | sed -n 's/^RUN_DIR=//p')"
[ -n "$RUN_DIR2" ] || { echo "FAIL: 分组运行未输出 RUN_DIR" >&2; echo "$OUT2" >&2; exit 1; }
grep -q '"language_id": "java"' "$RUN_DIR2/plan.json" || \
  { echo "FAIL: 分组运行 plan.json 仍须含 language_id=java" >&2; cat "$RUN_DIR2/plan.json" >&2; exit 1; }
grep -q '"semantic_grouping_enabled": true' "$RUN_DIR2/plan.json" || \
  { echo "FAIL: 适配器未把 CC_CODE_REVIEWER_SEMANTIC_GROUPS_FILE 透传给 core" >&2; cat "$RUN_DIR2/plan.json" >&2; exit 1; }
grep -Fq '"semantic_group_ids": ["grp-a"]' "$RUN_DIR2/batches/batch-001.json" || \
  { echo "FAIL: batch json 缺 semantic_group_ids" >&2; cat "$RUN_DIR2/batches/batch-001.json" >&2; exit 1; }

rm -rf "$TMP"
echo "PASS: java plan-file-batches uses core"
