#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase12-large.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

validate_json_file() {
  local file="$1"
  if command -v jq >/dev/null 2>&1; then
    jq empty "$file" >/dev/null
  else
    perl -MJSON::PP -0777 -ne 'decode_json($_)' "$file"
  fi
}

RUN_DIR="$TMP_DIR/run"
mkdir -p "$RUN_DIR/batches" "$RUN_DIR/results"

cat > "$RUN_DIR/plan.json" <<'JSON'
{
  "schema_version": 1,
  "run_id": "run-1",
  "project_name": "demo",
  "review_mode": "standard",
  "review_scope": "全量代码",
  "semantic_level": "maven-static",
  "total_java_loc": 50000,
  "total_java_file_count": 400,
  "batch_count": 2
}
JSON

cat > "$RUN_DIR/batches/batch-001.json" <<'JSON'
{
  "batch_id": "batch-001",
  "planned_java_loc": 25000,
  "planned_java_file_count": 200,
  "scan_roots": ["order-api"],
  "modules": [{"name": "order-api"}]
}
JSON
cat > "$RUN_DIR/batches/batch-002.json" <<'JSON'
{
  "batch_id": "batch-002",
  "planned_java_loc": 25000,
  "planned_java_file_count": 200,
  "scan_roots": ["payment"],
  "modules": [{"name": "payment"}]
}
JSON

cat > "$RUN_DIR/results/batch-001.status.json" <<JSON
{
  "batch_id": "batch-001",
  "status": "completed",
  "planned_java_loc": 25000,
  "planned_java_file_count": 200,
  "result_path": "$RUN_DIR/results/batch-001.md",
  "finding_count": 1
}
JSON
cat > "$RUN_DIR/results/batch-001.md" <<'MD'
# Batch 001

## 发现列表

### P1 | [维度1-正确性] 示例问题
- 文件：order-api/src/main/java/Demo.java:10
- 置信度：高
- 证据：示例证据
- 影响：示例影响
- 建议：示例建议

## 跨批依赖待复核
- payment 模块调用链需要在对应批次复核
MD

cat > "$RUN_DIR/results/batch-002.status.json" <<'JSON'
{
  "batch_id": "batch-002",
  "status": "failed",
  "planned_java_loc": 25000,
  "planned_java_file_count": 200,
  "error": "subagent failed"
}
JSON

set +e
OUTPUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 bash "$ROOT_DIR/scripts/phase12-merge-large-batches.sh" "$RUN_DIR" 2>&1)"
STATUS=$?
set -e
test "$STATUS" -ne 0
FINAL_REPORT="$(printf '%s\n' "$OUTPUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"

test -f "$RUN_DIR/summary.json"
test -f "$FINAL_REPORT"
validate_json_file "$RUN_DIR/summary.json"
grep -q '"completed_batches": 1' "$RUN_DIR/summary.json"
grep -q '"failed_batches": 1' "$RUN_DIR/summary.json"
grep -q '"pending_batches": 0' "$RUN_DIR/summary.json"
grep -q '"merge_blocked": true' "$RUN_DIR/summary.json"
grep -q '"java_loc_coverage_percent": 50' "$RUN_DIR/summary.json"
grep -q '\[合并阻塞\]' "$FINAL_REPORT"
grep -q "大仓库审查执行摘要" "$FINAL_REPORT"
grep -q "批次状态总览" "$FINAL_REPORT"
grep -q "batch-001.*已纳入本次合并" "$FINAL_REPORT"
grep -q "batch-002.*失败遗留" "$FINAL_REPORT"
grep -q "示例问题" "$FINAL_REPORT"
grep -q "跨批依赖线索" "$FINAL_REPORT"
grep -q "payment 模块调用链" "$FINAL_REPORT"

FULL_RUN_DIR="$TMP_DIR/full run"
mkdir -p "$FULL_RUN_DIR/batches" "$FULL_RUN_DIR/results"
cat > "$FULL_RUN_DIR/plan.json" <<'JSON'
{
  "run_id": "run-full",
  "project_name": "demo full",
  "review_mode": "standard",
  "review_scope": "全量代码",
  "semantic_level": "jdtls-lsp",
  "total_java_loc": 100,
  "total_java_file_count": 2,
  "batch_count": 1
}
JSON
cat > "$FULL_RUN_DIR/batches/batch-001.json" <<'JSON'
{"batch_id":"batch-001","planned_java_loc":100,"planned_java_file_count":2,"modules":[{"name":"core"}]}
JSON
cat > "$FULL_RUN_DIR/results/batch-001.status.json" <<JSON
{"batch_id":"batch-001","status":"completed","planned_java_loc":100,"planned_java_file_count":2,"result_path":"$FULL_RUN_DIR/results/batch-001.md","finding_count":0}
JSON
cat > "$FULL_RUN_DIR/results/batch-001.md" <<'MD'
## 发现列表

本批次未发现问题。
MD

FULL_OUTPUT="$(bash "$ROOT_DIR/scripts/phase12-merge-large-batches.sh" "$FULL_RUN_DIR")"
FULL_REPORT="$(printf '%s\n' "$FULL_OUTPUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
test -f "$FULL_REPORT"
if grep -q '\[阶段性\]' "$FULL_REPORT"; then
  echo "full report must not be marked staged" >&2
  exit 1
fi
grep -q '"java_loc_coverage_percent": 100' "$FULL_RUN_DIR/summary.json"

PARTIAL_RUN_DIR="$TMP_DIR/partial run"
mkdir -p "$PARTIAL_RUN_DIR/batches" "$PARTIAL_RUN_DIR/results"
cat > "$PARTIAL_RUN_DIR/plan.json" <<'JSON'
{
  "run_id": "run-partial",
  "project_name": "demo partial",
  "review_mode": "standard",
  "review_scope": "全量代码",
  "semantic_level": "maven-static",
  "total_java_loc": 300,
  "total_java_file_count": 6,
  "batch_count": 3
}
JSON
for batch_id in batch-001 batch-002 batch-003; do
  cat > "$PARTIAL_RUN_DIR/batches/$batch_id.json" <<JSON
{"batch_id":"$batch_id","planned_java_loc":100,"planned_java_file_count":2,"scan_roots":["$batch_id"],"modules":[{"name":"$batch_id"}]}
JSON
done
for batch_id in batch-001 batch-002; do
  cat > "$PARTIAL_RUN_DIR/results/$batch_id.status.json" <<JSON
{"batch_id":"$batch_id","status":"completed","planned_java_loc":100,"planned_java_file_count":2,"result_path":"$PARTIAL_RUN_DIR/results/$batch_id.md","finding_count":0}
JSON
  printf '## 发现列表\n\n%s 完成。\n' "$batch_id" > "$PARTIAL_RUN_DIR/results/$batch_id.md"
done
cat > "$PARTIAL_RUN_DIR/results/batch-003.status.json" <<'JSON'
{"batch_id":"batch-003","status":"pending","planned_java_loc":100,"planned_java_file_count":2}
JSON

PARTIAL_OUTPUT="$(RUN_BATCH_IDS="batch-001,batch-002" bash "$ROOT_DIR/scripts/phase12-merge-large-batches.sh" "$PARTIAL_RUN_DIR")"
PARTIAL_REPORT="$(printf '%s\n' "$PARTIAL_OUTPUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
test -f "$PARTIAL_REPORT"
grep -q '\[阶段性\]' "$PARTIAL_REPORT"
grep -q '"merge_blocked": false' "$PARTIAL_RUN_DIR/summary.json"
grep -q '"target_batch_count": 2' "$PARTIAL_RUN_DIR/summary.json"
grep -q "batch-001.*已纳入本次合并" "$PARTIAL_REPORT"
grep -q "batch-002.*已纳入本次合并" "$PARTIAL_REPORT"
grep -q "batch-003.*未纳入本轮，遗留" "$PARTIAL_REPORT"

PENDING_RUN_DIR="$TMP_DIR/pending run"
mkdir -p "$PENDING_RUN_DIR/batches" "$PENDING_RUN_DIR/results"
cat > "$PENDING_RUN_DIR/plan.json" <<'JSON'
{
  "run_id": "run-pending",
  "project_name": "demo pending",
  "review_mode": "standard",
  "review_scope": "全量代码",
  "semantic_level": "maven-static",
  "total_java_loc": 100,
  "total_java_file_count": 2,
  "batch_count": 1
}
JSON
cat > "$PENDING_RUN_DIR/batches/batch-001.json" <<'JSON'
{"batch_id":"batch-001","planned_java_loc":100,"planned_java_file_count":2,"modules":[{"name":"pending"}]}
JSON
cat > "$PENDING_RUN_DIR/results/batch-001.status.json" <<'JSON'
{"batch_id":"batch-001","status":"pending","planned_java_loc":100,"planned_java_file_count":2}
JSON
set +e
PENDING_OUTPUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 bash "$ROOT_DIR/scripts/phase12-merge-large-batches.sh" "$PENDING_RUN_DIR" 2>&1)"
PENDING_STATUS=$?
set -e
test "$PENDING_STATUS" -ne 0
PENDING_REPORT="$(printf '%s\n' "$PENDING_OUTPUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
test -f "$PENDING_REPORT"
grep -q '"wait_timed_out": true' "$PENDING_RUN_DIR/summary.json"
grep -q '\[合并阻塞\]' "$PENDING_REPORT"
grep -q "batch-001.*未完成遗留" "$PENDING_REPORT"
grep -q "等待本轮批次完成超时" "$PENDING_REPORT"

echo "PASS: phase12 large Maven batch merge"
