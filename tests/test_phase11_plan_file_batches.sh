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

for index in 1 2 3 4 5 6 7 8 9; do
  create_java_file "OrderService${index}.java" 9000
done

{
  echo "package com.example.order;"
  echo "public class OrderServiceTest {"
  seq 1 20000 | sed 's/.*/  public void test&() {}/'
  echo "}"
} > "$TEST_SRC_DIR/OrderServiceTest.java"

OUTPUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260602-010203 bash "$ROOT_DIR/scripts/phase11-plan-file-batches.sh" "$PROJECT_DIR" "standard" "main")"
RUN_DIR="$(printf '%s\n' "$OUTPUT" | sed -n 's/^RUN_DIR=//p')"
RUN_ID="$(printf '%s\n' "$OUTPUT" | sed -n 's/^RUN_ID=//p')"
BATCH_COUNT="$(printf '%s\n' "$OUTPUT" | sed -n 's/^BATCH_COUNT=//p')"

test "$RUN_ID" = "20260602-010203-main-standard"
test "$(basename "$RUN_DIR")" = "$RUN_ID"
test -d "$RUN_DIR"
test "$BATCH_COUNT" -ge 3
test -f "$RUN_DIR/batches/batch-001.files"
test -f "$RUN_DIR/batches/batch-001.json"
grep -q "TOTAL_JAVA_FILE_COUNT=9" <<< "$OUTPUT"

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

echo "PASS: phase11 file batch planner"
