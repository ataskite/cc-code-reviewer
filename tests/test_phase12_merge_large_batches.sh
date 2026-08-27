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

# Maven 大仓没有 batch_file_list；覆盖台账应基于冻结输入与 scan_roots 回填。
cat > "$RUN_DIR/review-input.json" <<'JSON'
{
  "schema_version": 1,
  "language_id": "java",
  "items": [
    {"path":"order-api/src/main/java/Demo.java","selected":true},
    {"path":"payment/src/main/java/Payment.java","selected":true}
  ]
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
OUTPUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$RUN_DIR" 2>&1)"
STATUS=$?
set -e
test "$STATUS" -ne 0
FINAL_REPORT="$(printf '%s\n' "$OUTPUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"

test -f "$RUN_DIR/summary.json"
test -f "$FINAL_REPORT"
test -f "$RUN_DIR/run-manifest.json"
validate_json_file "$RUN_DIR/summary.json"
validate_json_file "$RUN_DIR/run-manifest.json"
jq -e '.coverage | length == 2' "$RUN_DIR/run-manifest.json" >/dev/null
jq -e '.coverage[] | select(.path == "order-api/src/main/java/Demo.java" and .batch_id == "batch-001" and .status == "completed")' "$RUN_DIR/run-manifest.json" >/dev/null
jq -e '.coverage[] | select(.path == "payment/src/main/java/Payment.java" and .batch_id == "batch-002" and .status == "failed")' "$RUN_DIR/run-manifest.json" >/dev/null
jq -e '.terminal_state == "failed" and .coverage_sets.failed[0].failure_class == "unknown" and ((.coverage_sets.leftover | length) == 0)' "$RUN_DIR/run-manifest.json" >/dev/null
grep -q '"completed_batches": 1' "$RUN_DIR/summary.json"
grep -q '"failed_batches": 1' "$RUN_DIR/summary.json"
grep -q '"pending_batches": 0' "$RUN_DIR/summary.json"
grep -q '"merge_blocked": true' "$RUN_DIR/summary.json"
grep -q '"report_title": "\[合并阻塞\] 代码审查报告 - demo"' "$RUN_DIR/summary.json"
grep -q '"java_loc_coverage_percent": 50' "$RUN_DIR/summary.json"
head -n 1 "$FINAL_REPORT" | grep -Fx '# [合并阻塞] 代码审查报告 - demo'
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

FULL_OUTPUT="$(bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$FULL_RUN_DIR")"
FULL_REPORT="$(printf '%s\n' "$FULL_OUTPUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
test -f "$FULL_REPORT"
if grep -q '\[阶段性\]' "$FULL_REPORT"; then
  echo "full report must not be marked staged" >&2
  exit 1
fi
grep -q '"java_loc_coverage_percent": 100' "$FULL_RUN_DIR/summary.json"
grep -q '"report_title": "代码审查报告 - demo full"' "$FULL_RUN_DIR/summary.json"
head -n 1 "$FULL_REPORT" | grep -Fx '# 代码审查报告 - demo full'

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

PARTIAL_OUTPUT="$(RUN_BATCH_IDS="batch-001,batch-002" bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$PARTIAL_RUN_DIR")"
PARTIAL_REPORT="$(printf '%s\n' "$PARTIAL_OUTPUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
test -f "$PARTIAL_REPORT"
grep -q '\[阶段性\]' "$PARTIAL_REPORT"
grep -q '"merge_blocked": false' "$PARTIAL_RUN_DIR/summary.json"
grep -q '"target_batch_count": 2' "$PARTIAL_RUN_DIR/summary.json"
grep -q '"report_title": "\[阶段性\] 代码审查报告 - demo partial"' "$PARTIAL_RUN_DIR/summary.json"
head -n 1 "$PARTIAL_REPORT" | grep -Fx '# [阶段性] 代码审查报告 - demo partial'
grep -q "batch-001.*已纳入本次合并" "$PARTIAL_REPORT"
grep -q "batch-002.*已纳入本次合并" "$PARTIAL_REPORT"
grep -q "batch-003.*未纳入本轮，遗留" "$PARTIAL_REPORT"
grep -q "审查配置快照" "$PARTIAL_REPORT"
grep -q "审查范围说明" "$PARTIAL_REPORT"
grep -q "覆盖限制与未审查范围" "$PARTIAL_REPORT"

SUBSET_RUN_DIR="$TMP_DIR/subset completed run"
mkdir -p "$SUBSET_RUN_DIR/batches" "$SUBSET_RUN_DIR/results"
cat > "$SUBSET_RUN_DIR/plan.json" <<'JSON'
{
  "run_id": "run-subset",
  "project_name": "demo subset",
  "review_mode": "standard",
  "review_scope": "全量代码",
  "semantic_level": "maven-static",
  "total_java_loc": 300,
  "total_java_file_count": 6,
  "batch_count": 3
}
JSON
for batch_id in batch-001 batch-002 batch-003; do
  cat > "$SUBSET_RUN_DIR/batches/$batch_id.json" <<JSON
{"batch_id":"$batch_id","planned_java_loc":100,"planned_java_file_count":2,"scan_roots":["$batch_id"],"modules":[{"name":"$batch_id"}]}
JSON
  cat > "$SUBSET_RUN_DIR/results/$batch_id.status.json" <<JSON
{"batch_id":"$batch_id","status":"completed","planned_java_loc":100,"planned_java_file_count":2,"result_path":"$SUBSET_RUN_DIR/results/$batch_id.md","finding_count":1}
JSON
  printf '## 发现列表\n\n### P1 | [维度1-正确性] %s 问题\n- 文件：%s/src/main/java/Demo.java:10\n- 置信度：高\n- 证据：示例\n- 影响：示例\n- 建议：示例\n' "$batch_id" "$batch_id" > "$SUBSET_RUN_DIR/results/$batch_id.md"
done

SUBSET_OUTPUT="$(RUN_BATCH_IDS="batch-001,batch-002" bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$SUBSET_RUN_DIR")"
SUBSET_REPORT="$(printf '%s\n' "$SUBSET_OUTPUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
test -f "$SUBSET_REPORT"
grep -q '"merge_blocked": false' "$SUBSET_RUN_DIR/summary.json"
grep -q '"included_batches": 2' "$SUBSET_RUN_DIR/summary.json"
grep -q '"leftover_batches": 1' "$SUBSET_RUN_DIR/summary.json"
grep -q '"report_title": "\[阶段性\] 代码审查报告 - demo subset"' "$SUBSET_RUN_DIR/summary.json"
head -n 1 "$SUBSET_REPORT" | grep -Fx '# [阶段性] 代码审查报告 - demo subset'
grep -q "batch-003.*未纳入本轮，遗留" "$SUBSET_REPORT"

DEDUP_RUN_DIR="$TMP_DIR/dedup run"
mkdir -p "$DEDUP_RUN_DIR/batches" "$DEDUP_RUN_DIR/results"
cat > "$DEDUP_RUN_DIR/plan.json" <<'JSON'
{
  "run_id": "run-dedup",
  "project_name": "demo dedup",
  "review_mode": "standard",
  "review_scope": "全量代码",
  "semantic_level": "maven-static",
  "total_java_loc": 200,
  "total_java_file_count": 4,
  "batch_count": 2
}
JSON
for batch_id in batch-001 batch-002; do
  cat > "$DEDUP_RUN_DIR/batches/$batch_id.json" <<JSON
{"batch_id":"$batch_id","planned_java_loc":100,"planned_java_file_count":2,"scan_roots":["$batch_id"],"modules":[{"name":"$batch_id"}]}
JSON
  cat > "$DEDUP_RUN_DIR/results/$batch_id.status.json" <<JSON
{"batch_id":"$batch_id","status":"completed","planned_java_loc":100,"planned_java_file_count":2,"result_path":"$DEDUP_RUN_DIR/results/$batch_id.md","finding_count":1}
JSON
  cat > "$DEDUP_RUN_DIR/results/$batch_id.md" <<'MD'
## 发现列表

### P1 | [维度1-正确性] 重复问题
- 文件：shared/src/main/java/Demo.java:10
- 置信度：高
- 证据：相同证据
- 影响：相同影响
- 建议：相同建议
MD
done

DEDUP_OUTPUT="$(bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$DEDUP_RUN_DIR")"
DEDUP_REPORT="$(printf '%s\n' "$DEDUP_OUTPUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
test -f "$DEDUP_REPORT"
grep -q '"finding_count": 1' "$DEDUP_RUN_DIR/summary.json"
grep -qF '"dedup": {"input_findings": 2, "merged_duplicates": 1, "output_findings": 1}' "$DEDUP_RUN_DIR/summary.json"
test "$(grep -c '### P1 | \[维度1-正确性\] 重复问题' "$DEDUP_REPORT")" = "1"

# 内容指纹去重（Java）：同一缺陷两批次措辞不同但 文件×维度×证据代码 一致 → 合并。
# 行号漂移、围栏缩进、围栏内空行、建议句序交换均不改变指纹；保留首现批次原文，
# summary.json 的 dedup 对象与报告“跨批次去重”披露行必须同步出现。
PARA_RUN_DIR="$TMP_DIR/paraphrase run"
mkdir -p "$PARA_RUN_DIR/batches" "$PARA_RUN_DIR/results"
cat > "$PARA_RUN_DIR/plan.json" <<'JSON'
{
  "run_id": "run-paraphrase",
  "project_name": "demo paraphrase",
  "review_mode": "standard",
  "review_scope": "全量代码",
  "semantic_level": "maven-static",
  "total_java_loc": 200,
  "total_java_file_count": 4,
  "batch_count": 2
}
JSON
for batch_id in batch-001 batch-002; do
  cat > "$PARA_RUN_DIR/batches/$batch_id.json" <<JSON
{"batch_id":"$batch_id","planned_java_loc":100,"planned_java_file_count":2,"scan_roots":["shared"],"modules":[{"name":"shared"}]}
JSON
  cat > "$PARA_RUN_DIR/results/$batch_id.status.json" <<JSON
{"batch_id":"$batch_id","status":"completed","planned_java_loc":100,"planned_java_file_count":2,"result_path":"$PARA_RUN_DIR/results/$batch_id.md","finding_count":1}
JSON
done
cat > "$PARA_RUN_DIR/results/batch-001.md" <<'MD'
## 发现列表

### P1 | [维度1-正确性] 空指针解引用风险
- 文件：shared/src/main/java/Demo.java:11
- 置信度：高
- 证据：
  ```java
  String name = config.get("name");
  return name.trim();
  ```
- 建议：先判空；再调用方法
MD
cat > "$PARA_RUN_DIR/results/batch-002.md" <<'MD'
## 发现列表

### P1 | [维度1-正确性] 未判空直接调用实例方法
- 文件：shared/src/main/java/Demo.java:42
- 证据：
      ```java
      String name = config.get("name");

      return name.trim();
      ```
- 建议：再调用方法；先判空
MD
PARA_OUTPUT="$(bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$PARA_RUN_DIR")"
PARA_SUMM="$(printf '%s\n' "$PARA_OUTPUT" | sed -n 's/^SUMMARY_PATH=//p')"
PARA_REPORT="$(printf '%s\n' "$PARA_OUTPUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
test -f "$PARA_REPORT"
validate_json_file "$PARA_SUMM"
grep -q '"finding_count": 1' "$PARA_SUMM"
grep -qF '"dedup": {"input_findings": 2, "merged_duplicates": 1, "output_findings": 1}' "$PARA_SUMM"
grep -qF '跨批次去重：2 条发现中合并重复 1 条（按文件 × 维度 × 证据代码指纹），保留 1 条。' "$PARA_REPORT"
test "$(grep -c '^### P1 | \[维度1-正确性\]' "$PARA_REPORT")" = "1"
grep -q '空指针解引用风险' "$PARA_REPORT"
if grep -q '未判空直接调用实例方法' "$PARA_REPORT"; then
  echo "FAIL: 同指纹改写块必须整块丢弃，只保留首现批次标题" >&2
  exit 1
fi

# 待确认块同权参与指纹身份：仅有「文件行」没有围栏的定位块按 路径×维度×空证据 合并；
# 其他文件的待确认与带围栏的 P0 对照块全部存活；统计对全部输入口径一致。
TODO_RUN_DIR="$TMP_DIR/todo parity run"
mkdir -p "$TODO_RUN_DIR/batches" "$TODO_RUN_DIR/results"
cat > "$TODO_RUN_DIR/plan.json" <<'JSON'
{
  "run_id": "run-todo-parity",
  "project_name": "demo todo parity",
  "review_mode": "standard",
  "review_scope": "全量代码",
  "semantic_level": "maven-static",
  "total_java_loc": 200,
  "total_java_file_count": 4,
  "batch_count": 2
}
JSON
for batch_id in batch-001 batch-002; do
  cat > "$TODO_RUN_DIR/batches/$batch_id.json" <<JSON
{"batch_id":"$batch_id","planned_java_loc":100,"planned_java_file_count":2,"scan_roots":["shared"],"modules":[{"name":"shared"}]}
JSON
  cat > "$TODO_RUN_DIR/results/$batch_id.status.json" <<JSON
{"batch_id":"$batch_id","status":"completed","planned_java_loc":100,"planned_java_file_count":2,"result_path":"$TODO_RUN_DIR/results/$batch_id.md","finding_count":1}
JSON
done
cat > "$TODO_RUN_DIR/results/batch-001.md" <<'MD'
## 发现列表

### 待确认 [维度12-测试盲区] 缺少空集合边界用例
- 文件：shared/src/main/java/Demo.java

### 待确认 [维度12-测试盲区] 支付空态页面未覆盖
- 文件：payment/src/main/java/Payment.java
MD
cat > "$TODO_RUN_DIR/results/batch-002.md" <<'MD'
## 发现列表

### 待确认 [维度12-测试盲区] 集合判空逻辑待复核
- 置信度：中
- 文件：shared/src/main/java/Demo.java

### P0 | [维度5-安全] 密钥硬编码在源码中
- 文件：payment/src/main/java/PaymentKeys.java:6
- 证据：
  ```java
  private static final String SECRET = "s3cr3t";
  ```
MD
TODO_OUTPUT="$(bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$TODO_RUN_DIR")"
TODO_SUMM="$(printf '%s\n' "$TODO_OUTPUT" | sed -n 's/^SUMMARY_PATH=//p')"
TODO_REPORT="$(printf '%s\n' "$TODO_OUTPUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
test -f "$TODO_REPORT"
validate_json_file "$TODO_SUMM"
grep -q '"finding_count": 3' "$TODO_SUMM"
grep -qF '"dedup": {"input_findings": 4, "merged_duplicates": 1, "output_findings": 3}' "$TODO_SUMM"
grep -qF '跨批次去重：4 条发现中合并重复 1 条（按文件 × 维度 × 证据代码指纹），保留 3 条。' "$TODO_REPORT"
grep -q '缺少空集合边界用例' "$TODO_REPORT"
if grep -q '集合判空逻辑待复核' "$TODO_REPORT"; then
  echo "FAIL: 定位块（无围栏）同路径同维度的待确认重复必须按指纹合并" >&2
  exit 1
fi
grep -q '支付空态页面未覆盖' "$TODO_REPORT"
grep -q '密钥硬编码在源码中' "$TODO_REPORT"

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
PENDING_OUTPUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$PENDING_RUN_DIR" 2>&1)"
PENDING_STATUS=$?
set -e
test "$PENDING_STATUS" -ne 0
PENDING_REPORT="$(printf '%s\n' "$PENDING_OUTPUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
test -f "$PENDING_REPORT"
grep -q '"wait_timed_out": true' "$PENDING_RUN_DIR/summary.json"
grep -q '\[合并阻塞\]' "$PENDING_REPORT"
grep -q "batch-001.*未完成遗留" "$PENDING_REPORT"
grep -q "等待本轮批次完成超时" "$PENDING_REPORT"

# partial（部分完成）批次：目标批次有结果 → 发现纳入合并、覆盖保守不计、manifest 标记 partial
PARTIAL_STATUS_RUN_DIR="$TMP_DIR/partial status run"
mkdir -p "$PARTIAL_STATUS_RUN_DIR/batches" "$PARTIAL_STATUS_RUN_DIR/results"
cat > "$PARTIAL_STATUS_RUN_DIR/plan.json" <<'JSON'
{
  "schema_version": 1,
  "run_id": "run-partial-status",
  "project_name": "demo partial status",
  "review_mode": "standard",
  "review_scope": "全量代码",
  "semantic_level": "maven-static",
  "total_java_loc": 50000,
  "total_java_file_count": 400,
  "batch_count": 2
}
JSON
cat > "$PARTIAL_STATUS_RUN_DIR/batches/batch-001.json" <<'JSON'
{"batch_id":"batch-001","planned_java_loc":25000,"planned_java_file_count":200,"scan_roots":["order-api"],"modules":[{"name":"order-api"}]}
JSON
cat > "$PARTIAL_STATUS_RUN_DIR/batches/batch-002.json" <<'JSON'
{"batch_id":"batch-002","planned_java_loc":25000,"planned_java_file_count":200,"scan_roots":["payment"],"modules":[{"name":"payment"}]}
JSON
cat > "$PARTIAL_STATUS_RUN_DIR/review-input.json" <<'JSON'
{
  "schema_version": 1,
  "language_id": "java",
  "items": [
    {"path":"order-api/src/main/java/Demo.java","selected":true},
    {"path":"payment/src/main/java/Payment.java","selected":true}
  ]
}
JSON
cat > "$PARTIAL_STATUS_RUN_DIR/results/batch-001.status.json" <<JSON
{"batch_id":"batch-001","status":"partial","planned_java_loc":25000,"planned_java_file_count":200,
 "result_path":"$PARTIAL_STATUS_RUN_DIR/results/batch-001.md","finding_count":1,"error":"subagent interrupted"}
JSON
cat > "$PARTIAL_STATUS_RUN_DIR/results/batch-001.md" <<'MD'
# Batch 001

## 发现列表

### P1 | [维度1-正确性] 部分完成示例问题
- 文件：order-api/src/main/java/Demo.java:10
- 置信度：高
- 证据：示例证据
- 影响：示例影响
- 建议：示例建议

## 覆盖情况
- 中断前已覆盖 order-api 全部 controller
MD

set +e
PARTIAL_STATUS_OUTPUT="$(RUN_BATCH_IDS="batch-001" bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$PARTIAL_STATUS_RUN_DIR" 2>&1)"
PARTIAL_STATUS=$?
set -e
test "$PARTIAL_STATUS" -eq 0
PARTIAL_STATUS_REPORT="$(printf '%s\n' "$PARTIAL_STATUS_OUTPUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
test -f "$PARTIAL_STATUS_REPORT"
validate_json_file "$PARTIAL_STATUS_RUN_DIR/summary.json"
validate_json_file "$PARTIAL_STATUS_RUN_DIR/run-manifest.json"
grep -qF '"partial_batches": 1' "$PARTIAL_STATUS_RUN_DIR/summary.json"
grep -qF '"partial_batch_ids": ["batch-001"]' "$PARTIAL_STATUS_RUN_DIR/summary.json"
grep -qF '"included_batches": 0' "$PARTIAL_STATUS_RUN_DIR/summary.json"
grep -q '"finding_count": 1' "$PARTIAL_STATUS_RUN_DIR/summary.json"
grep -q '"covered_java_file_count": 0' "$PARTIAL_STATUS_RUN_DIR/summary.json"
grep -q '"merge_blocked": false' "$PARTIAL_STATUS_RUN_DIR/summary.json"
grep -q '"report_title": "\[阶段性\] 代码审查报告 - demo partial status"' "$PARTIAL_STATUS_RUN_DIR/summary.json"
head -n 1 "$PARTIAL_STATUS_REPORT" | grep -Fx '# [阶段性] 代码审查报告 - demo partial status'
grep -q "大仓库审查执行摘要" "$PARTIAL_STATUS_REPORT"
grep -q "部分完成待重跑批次：1" "$PARTIAL_STATUS_REPORT"
# 「subagent interrupted」未显式声明归因 → 关键词回退（interrupt ∈ 取消族）→ cancelled；
# partial 台账不再使用字面量 "partial"，统一携带解析后的封闭枚举值。
grep -qF '| batch-001 | 部分完成待重跑 | 是 | 部分完成已纳入 | 200 | 25000 | order-api | [已取消] subagent interrupted |' "$PARTIAL_STATUS_REPORT"
grep -q "中断前已覆盖 order-api 全部 controller" "$PARTIAL_STATUS_REPORT"
jq -e '.coverage[] | select(.path == "order-api/src/main/java/Demo.java" and .batch_id == "batch-001" and .status == "partial" and .failure_class == "cancelled")' "$PARTIAL_STATUS_RUN_DIR/run-manifest.json" >/dev/null
jq -e '.coverage_sets.selected[] | select(.path == "order-api/src/main/java/Demo.java" and .failure_class == "cancelled")' "$PARTIAL_STATUS_RUN_DIR/run-manifest.json" >/dev/null
jq -e '.terminal_state == "partial"' "$PARTIAL_STATUS_RUN_DIR/run-manifest.json" >/dev/null
# partial 批次的 item_id 与 completed 派生一致：同一 path 的 item_id 只依赖路径与仓库身份
jq -e '(.coverage[] | select(.path == "order-api/src/main/java/Demo.java") | .item_id | length) == 64' "$PARTIAL_STATUS_RUN_DIR/run-manifest.json" >/dev/null

# ---- 失败归因（failure_class，端到端）：failed 显式封闭枚举值 → manifest 逐字透传
# + 错误列「[中文短标签] 」前缀；发明枚举外值视为未填写走关键词回退；显式 unknown
# 优先于关键词命中。summary 的 failed_by_class 只统计 FAILED 批次（五键齐全、含 0），
# 与 failed_batches 计数守恒；partial 不计入该对象。 ----
CLASS_RUN_DIR="$TMP_DIR/failure class run"
mkdir -p "$CLASS_RUN_DIR/batches" "$CLASS_RUN_DIR/results"
cat > "$CLASS_RUN_DIR/plan.json" <<'JSON'
{
  "schema_version": 1,
  "run_id": "run-class",
  "project_name": "demo class",
  "review_mode": "standard",
  "review_scope": "全量代码",
  "semantic_level": "maven-static",
  "total_java_loc": 50000,
  "total_java_file_count": 400,
  "batch_count": 2
}
JSON
cat > "$CLASS_RUN_DIR/batches/batch-001.json" <<'JSON'
{"batch_id":"batch-001","planned_java_loc":25000,"planned_java_file_count":200,"scan_roots":["order-api"],"modules":[{"name":"order-api"}]}
JSON
cat > "$CLASS_RUN_DIR/batches/batch-002.json" <<'JSON'
{"batch_id":"batch-002","planned_java_loc":25000,"planned_java_file_count":200,"scan_roots":["payment"],"modules":[{"name":"payment"}]}
JSON
cat > "$CLASS_RUN_DIR/review-input.json" <<'JSON'
{
  "schema_version": 1,
  "language_id": "java",
  "items": [
    {"path":"order-api/src/main/java/Demo.java","selected":true},
    {"path":"payment/src/main/java/Payment.java","selected":true}
  ]
}
JSON
cat > "$CLASS_RUN_DIR/results/batch-001.status.json" <<JSON
{"batch_id":"batch-001","status":"completed","planned_java_loc":25000,"planned_java_file_count":200,
 "result_path":"$CLASS_RUN_DIR/results/batch-001.md","finding_count":0}
JSON
cat > "$CLASS_RUN_DIR/results/batch-001.md" <<'MD'
## 发现列表

本批次未发现问题。
MD
run_class_merge() {
  set +e
  CLASS_OUTPUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$CLASS_RUN_DIR" 2>&1)"
  CLASS_STATUS=$?
  set -e
}

# 变体 1：显式 tool_budget_exhausted → manifest 逐字透传 + 错误列 [工具预算耗尽] 前缀；
# failed_by_class 对应键计数为 1，其余四键为 0（形状稳定 pin）。
cat > "$CLASS_RUN_DIR/results/batch-002.status.json" <<'JSON'
{"batch_id":"batch-002","status":"failed",
 "failure_class":"tool_budget_exhausted","error":"worker died unexpectedly"}
JSON
run_class_merge
test "$CLASS_STATUS" -eq 2
validate_json_file "$CLASS_RUN_DIR/run-manifest.json"
jq -e '.coverage_sets.failed[0].failure_class == "tool_budget_exhausted"' "$CLASS_RUN_DIR/run-manifest.json" >/dev/null
jq -e '.coverage[] | select(.path == "payment/src/main/java/Payment.java" and .failure_class == "tool_budget_exhausted" and .status == "failed")' "$CLASS_RUN_DIR/run-manifest.json" >/dev/null
jq -e '.failed_by_class == {"context_exhausted":0,"tool_budget_exhausted":1,"output_truncated":0,"cancelled":0,"unknown":0}' "$CLASS_RUN_DIR/summary.json" >/dev/null
jq -e '([.failed_by_class | .[]] | add) == .failed_batches' "$CLASS_RUN_DIR/summary.json" >/dev/null
CLASS_REPORT="$(printf '%s\n' "$CLASS_OUTPUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
grep -qF '| batch-002 | 失败 | 是 | 失败遗留 | 200 | 25000 | payment | [工具预算耗尽] worker died unexpectedly |' "$CLASS_REPORT"

# 变体 2：发明枚举外值 → 视为未填写，关键词回退；「timed out」不属于任何回退词族
# → unknown，错误列加 [未知] 前缀。
cat > "$CLASS_RUN_DIR/results/batch-002.status.json" <<'JSON'
{"batch_id":"batch-002","status":"failed",
 "failure_class":"queue_full_forever","error":"merge window timed out"}
JSON
run_class_merge
jq -e '.coverage_sets.failed[0].failure_class == "unknown"' "$CLASS_RUN_DIR/run-manifest.json" >/dev/null
jq -e '.failed_by_class.unknown == 1 and .failed_by_class.context_exhausted == 0' "$CLASS_RUN_DIR/summary.json" >/dev/null
CLASS_REPORT="$(printf '%s\n' "$CLASS_OUTPUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
grep -qF '| batch-002 | 失败 | 是 | 失败遗留 | 200 | 25000 | payment | [未知] merge window timed out |' "$CLASS_REPORT"

# 变体 3：显式 unknown 属于封闭枚举 → 直接采用并压过关键词命中（error 含 cancel 本会
# 归为 cancelled），错误列加 [未知] 前缀。
cat > "$CLASS_RUN_DIR/results/batch-002.status.json" <<'JSON'
{"batch_id":"batch-002","status":"failed",
 "failure_class":"unknown","error":"model provider dropped after cancel request"}
JSON
run_class_merge
jq -e '.coverage_sets.failed[0].failure_class == "unknown"' "$CLASS_RUN_DIR/run-manifest.json" >/dev/null
jq -e '.coverage_sets.failed[0].reason == "model provider dropped after cancel request"' "$CLASS_RUN_DIR/run-manifest.json" >/dev/null
CLASS_REPORT="$(printf '%s\n' "$CLASS_OUTPUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
grep -qF '| batch-002 | 失败 | 是 | 失败遗留 | 200 | 25000 | payment | [未知] model provider dropped after cancel request |' "$CLASS_REPORT"

# 变体 4：partial 批次不改变 failed_by_class —— 只有 completed+partial、零 failed 时，
# summary 必须整体省略该对象（partial 永不计入失败归因统计）。
PARTIAL_ONLY_RUN="$TMP_DIR/partial only class run"
mkdir -p "$PARTIAL_ONLY_RUN/batches" "$PARTIAL_ONLY_RUN/results"
cat > "$PARTIAL_ONLY_RUN/plan.json" <<'JSON'
{
  "schema_version": 1,
  "run_id": "run-class-partial-only",
  "project_name": "demo class",
  "review_mode": "standard",
  "review_scope": "全量代码",
  "semantic_level": "maven-static",
  "total_java_loc": 50000,
  "total_java_file_count": 400,
  "batch_count": 2
}
JSON
cp "$CLASS_RUN_DIR/review-input.json" "$PARTIAL_ONLY_RUN/review-input.json"
cp "$CLASS_RUN_DIR/batches/batch-001.json" "$PARTIAL_ONLY_RUN/batches/"
cp "$CLASS_RUN_DIR/batches/batch-002.json" "$PARTIAL_ONLY_RUN/batches/"
cp "$CLASS_RUN_DIR/results/batch-001.status.json" "$PARTIAL_ONLY_RUN/results/batch-001.status.json"
cp "$CLASS_RUN_DIR/results/batch-001.md" "$PARTIAL_ONLY_RUN/results/batch-001.md"
cat > "$PARTIAL_ONLY_RUN/results/batch-002.md" <<'MD'
## 发现列表

### P1 | [维度1-正确性] partial 计数隔离示例
- 文件：payment/src/main/java/Payment.java:7

## 覆盖情况
- 中断前已覆盖 payment 全部 controller
MD
cat > "$PARTIAL_ONLY_RUN/results/batch-002.status.json" <<JSON
{"batch_id":"batch-002","status":"partial","finding_count":1,
 "failure_class":"context_exhausted","error":"上下文不足以完成整批",
 "result_path":"$PARTIAL_ONLY_RUN/results/batch-002.md"}
JSON
set +e
PO_OUTPUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$PARTIAL_ONLY_RUN" 2>&1)"
PO_STATUS=$?
set -e
if grep -q '"failed_by_class"' "$PARTIAL_ONLY_RUN/summary.json"; then
  echo "FAIL: 零 failed 且有 partial 时 summary 不得包含 failed_by_class 对象" >&2
  exit 1
fi

echo "PASS: phase12 large Maven batch merge"
