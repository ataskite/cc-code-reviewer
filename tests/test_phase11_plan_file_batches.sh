#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase11-file.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_DIR="$TMP_DIR/maven-single"
SRC_DIR="$PROJECT_DIR/src/main/java/com/example/order"
TEST_SRC_DIR="$PROJECT_DIR/src/test/java/com/example/order"
mkdir -p "$SRC_DIR" "$TEST_SRC_DIR"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
SRC_DIR="$PROJECT_DIR/src/main/java/com/example/order"
TEST_SRC_DIR="$PROJECT_DIR/src/test/java/com/example/order"

cat > "$PROJECT_DIR/pom.xml" <<'XML'
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>maven-single</artifactId>
  <version>1.0</version>
</project>
XML

create_java_file() {
  local file="$1"
  local lines="$2"
  {
    echo "package com.example.order;"
    echo "public class $(basename "$file" .java) {"
    seq 1 "$lines" | sed 's/.*/  public void m&() {}/'
    echo "}"
  } > "$SRC_DIR/$file"
}

for index in $(seq 1 20); do
  create_java_file "OrderService${index}.java" 9000
done

{
  echo "package com.example.order;"
  echo "public class OrderServiceTest {"
  seq 1 20000 | sed 's/.*/  public void test&() {}/'
  echo "}"
} > "$TEST_SRC_DIR/OrderServiceTest.java"

OUTPUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260602-010203 bash "$ROOT_DIR/scripts/languages/java/plan-file-batches.sh" "$PROJECT_DIR" "standard" "main")"
RUN_DIR="$(printf '%s\n' "$OUTPUT" | sed -n 's/^RUN_DIR=//p')"
RUN_ID="$(printf '%s\n' "$OUTPUT" | sed -n 's/^RUN_ID=//p')"
BATCH_COUNT="$(printf '%s\n' "$OUTPUT" | sed -n 's/^BATCH_COUNT=//p')"

test "$RUN_ID" = "20260602-010203-main-standard"
test "$(basename "$RUN_DIR")" = "$RUN_ID"
test -d "$RUN_DIR"
test "$BATCH_COUNT" -ge 2
test -f "$RUN_DIR/batches/batch-001.files"
test -f "$RUN_DIR/batches/batch-001.json"
grep -q "TOTAL_JAVA_FILE_COUNT=20" <<< "$OUTPUT"
grep -q '"batch_token_budget": 500000' "$RUN_DIR/plan.json"
grep -q '"context_window_tokens": 1000000' "$RUN_DIR/plan.json"

printf '%s\n' "$OUTPUT" | grep -q "简要分批计划"
printf '%s\n' "$OUTPUT" | grep -q "批次 行数 文件 重点范围"
printf '%s\n' "$OUTPUT" | grep -q "batch-001"
printf '%s\n' "$OUTPUT" | grep -q "OrderService"
printf '%s\n' "$OUTPUT" | grep -q "等"
printf '%s\n' "$OUTPUT" | grep -q "BATCH_FILE_LIST_DIR=$RUN_DIR/batches"

if ! grep -q "$PROJECT_DIR/src/main/java/com/example/order/OrderService" "$RUN_DIR/batches/batch-001.files"; then
  echo "file batch planner must write absolute Java file paths for batch agents" >&2
  exit 1
fi
if grep -R "src/test/java" "$RUN_DIR/batches" >/dev/null 2>&1; then
  echo "file batch planner must not include Java test sources" >&2
  exit 1
fi

# 语义亲和分组透传（additive）：Java 适配器把 CC_CODE_REVIEWER_SEMANTIC_GROUPS_FILE 与预算
# 透传给 core/plan-file-batches.sh。每个 OrderService 文件 loc=9003 → cost=27509，
# 预算 60000 → 每批恰 2 个文件（55018 ≤ 60000 < 82527），20 个文件共 10 批；
# 未分组文件（空组键排在 order-core 前）先按普通 first-fit 填满前 9 批，
# OrderService1/2 只能落进 batch-010，且因同组键必须同批。
# groups 文件使用仓库相对路径，验证 PROJECT_DIR 相对解析。
GROUPS_FILE="$PROJECT_DIR/semantic-groups.tsv"
{
  printf 'order-core\tsrc/main/java/com/example/order/OrderService1.java\n'
  printf 'order-core\tsrc/main/java/com/example/order/OrderService2.java\n'
} > "$GROUPS_FILE"
GROUP_OUTPUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260826-050000 \
                CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET=60000 \
                CC_CODE_REVIEWER_SEMANTIC_GROUPS_FILE="$GROUPS_FILE" \
                bash "$ROOT_DIR/scripts/languages/java/plan-file-batches.sh" "$PROJECT_DIR" "standard" "main")"
GROUP_RUN_DIR="$(printf '%s\n' "$GROUP_OUTPUT" | sed -n 's/^RUN_DIR=//p')"
GROUP_BATCH_COUNT="$(printf '%s\n' "$GROUP_OUTPUT" | sed -n 's/^BATCH_COUNT=//p')"

test "$GROUP_BATCH_COUNT" -eq 10
test "$GROUP_RUN_DIR" != "$RUN_DIR"
grep -q "TOTAL_JAVA_FILE_COUNT=20" <<< "$GROUP_OUTPUT"
grep -q '"language_id": "java"' "$GROUP_RUN_DIR/plan.json"
grep -q '"semantic_grouping_enabled": true' "$GROUP_RUN_DIR/plan.json"
grep -q "\"semantic_groups_path\": \".*$(basename "$GROUPS_FILE")\"" "$GROUP_RUN_DIR/plan.json"
if grep -R "src/test/java" "$GROUP_RUN_DIR/batches" >/dev/null 2>&1; then
  echo "grouped run must still not include Java test sources" >&2
  exit 1
fi
GROUP_SAME_BATCH=""
for files_list in "$GROUP_RUN_DIR"/batches/*.files; do
  if grep -Fq "src/main/java/com/example/order/OrderService1.java" "$files_list" && \
     grep -Fq "src/main/java/com/example/order/OrderService2.java" "$files_list"; then
    GROUP_SAME_BATCH="$files_list"
  fi
done
if [ -z "$GROUP_SAME_BATCH" ]; then
  echo "grouped Java fixture files must land in the same batch" >&2
  exit 1
fi
grep -Fq '"semantic_group_ids": ["order-core"]' "${GROUP_SAME_BATCH%.files}.json" || {
  echo "batch json for grouped batch must disclose semantic_group_ids" >&2
  cat "${GROUP_SAME_BATCH%.files}.json" >&2
  exit 1
}

echo "PASS: phase11 file batch planner"
