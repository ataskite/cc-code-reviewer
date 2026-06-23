#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/java-baseline.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_DIR="$TMP_DIR/maven-single"
SRC_DIR="$PROJECT_DIR/src/main/java/com/example"
mkdir -p "$SRC_DIR"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
cat > "$PROJECT_DIR/pom.xml" <<'XML'
<project><modelVersion>4.0.0</modelVersion>
<groupId>com.example</groupId><artifactId>maven-single</artifactId><version>1.0</version>
</project>
XML
cat > "$SRC_DIR/Foo.java" <<'JAVA'
package com.example; public class Foo { public void m() {} }
JAVA

OUTPUT="$(bash "$ROOT_DIR/scripts/phase3-project-scan.sh" "$PROJECT_DIR")"

# Java 用户可见输出字段必须保持不变
grep -q "项目类型: Maven" <<< "$OUTPUT"
grep -q "PROJECT_TYPE=maven-single" <<< "$OUTPUT"
grep -q "Java文件总数: 1" <<< "$OUTPUT"
grep -q "模块类型: 单模块项目" <<< "$OUTPUT"
# TECH_STACK 行格式不变（即使未识别也必须输出兜底行）
grep -q "TECH_STACK:" <<< "$OUTPUT"

echo "PASS: java baseline prescan contract"

# === 文件批次 planner 字段契约（现有 phase11-plan-file-batches.sh）===
SRC2="$PROJECT_DIR/src/main/java/com/example/svc"
mkdir -p "$SRC2"
for i in 1 2 3 4 5; do
  { echo "package com.example.svc;"; echo "public class S${i} {"; seq 1 9000 | sed 's/.*/  public void m&() {}/'; echo "}"; } > "$SRC2/S${i}.java"
done

BOUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260623-000000 bash "$ROOT_DIR/scripts/phase11-plan-file-batches.sh" "$PROJECT_DIR" "standard" "main")"
grep -q "RUN_ID=" <<< "$BOUT"
grep -q "RUN_DIR=" <<< "$BOUT"
grep -q "BATCH_COUNT=" <<< "$BOUT"
grep -q "TOTAL_JAVA_FILE_COUNT=" <<< "$BOUT"
grep -q "TOTAL_JAVA_LOC=" <<< "$BOUT"
grep -q "BATCH_FILE_LIST_DIR=" <<< "$BOUT"
grep -q "简要分批计划" <<< "$BOUT"
BRUN_DIR="$(printf '%s\n' "$BOUT" | sed -n 's/^RUN_DIR=//p')"
grep -q '"strategy": "file-token-batching"' "$BRUN_DIR/plan.json"
grep -q '"schema_version": 1' "$BRUN_DIR/plan.json"
test -f "$BRUN_DIR/batches/batch-001.files"
test -f "$BRUN_DIR/batches/batch-001.json"

echo "PASS: java baseline file-batch planner contract"

# === 合并报告字段契约（现有 phase12-merge-large-batches.sh）===
LRUN_DIR="$TMP_DIR/large-run"
mkdir -p "$LRUN_DIR/batches" "$LRUN_DIR/results"
cat > "$LRUN_DIR/plan.json" <<'JSON'
{"schema_version":1,"run_id":"r1","project_name":"demo","review_mode":"standard",
 "review_scope":"全量代码","semantic_level":"maven-static",
 "total_java_loc":500,"total_java_file_count":2,"batch_count":1}
JSON
cat > "$LRUN_DIR/batches/batch-001.json" <<'JSON'
{"batch_id":"batch-001","planned_java_loc":500,"planned_java_file_count":2,
 "scan_roots":["src"],"modules":[{"name":"root"}]}
JSON
cat > "$LRUN_DIR/results/batch-001.status.json" <<JSON
{"batch_id":"batch-001","status":"completed","planned_java_loc":500,
 "planned_java_file_count":2,"result_path":"$LRUN_DIR/results/batch-001.md","finding_count":0}
JSON
cat > "$LRUN_DIR/results/batch-001.md" <<'MD'
# Batch 001
## 发现列表
（无正式发现）
MD
MOUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 bash "$ROOT_DIR/scripts/phase12-merge-large-batches.sh" "$LRUN_DIR")"
grep -q "SUMMARY_PATH=" <<< "$MOUT"
grep -q "FINAL_REPORT_PATH=" <<< "$MOUT"
SUMMARY="$(printf '%s\n' "$MOUT" | sed -n 's/^SUMMARY_PATH=//p')"
grep -q '"report_title"' "$SUMMARY"
grep -q '"finding_count"' "$SUMMARY"
grep -q '"java_file_coverage_percent"' "$SUMMARY"
REPORT="$(printf '%s\n' "$MOUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
head -n1 "$REPORT" | grep -q '^# '

echo "PASS: java baseline merge report contract"
