#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/core-merge.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

RUN_DIR="$TMP_DIR/run"; mkdir -p "$RUN_DIR/batches" "$RUN_DIR/results"
cat > "$RUN_DIR/plan.json" <<'JSON'
{"schema_version":1,"run_id":"r1","project_name":"demo","review_mode":"standard",
 "review_scope":"全量代码","language_id":"frontend",
 "total_source_loc":500,"total_source_file_count":2,"batch_count":2}
JSON
cat > "$RUN_DIR/batches/batch-001.json" <<'JSON'
{"batch_id":"batch-001","planned_source_loc":250,"planned_source_file_count":1,
 "scan_roots":["src/a"],"modules":[{"name":"a"}]}
JSON
cat > "$RUN_DIR/batches/batch-002.json" <<'JSON'
{"batch_id":"batch-002","planned_source_loc":250,"planned_source_file_count":1,
 "scan_roots":["src/b"],"modules":[{"name":"b"}]}
JSON
cat > "$RUN_DIR/results/batch-001.status.json" <<JSON
{"batch_id":"batch-001","status":"completed","planned_source_loc":250,
 "planned_source_file_count":1,"result_path":"$RUN_DIR/results/batch-001.md","finding_count":1}
JSON
cat > "$RUN_DIR/results/batch-001.md" <<'MD'
# Batch 001
## 发现列表
### P1 | [维度4-状态与数据请求] 示例
- 文件：src/a/x.tsx:10
- 证据：示例
- 建议：示例
MD

# batch-002 未完成 → 合并阻塞
MOUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 RUN_BATCH_IDS=batch-001,batch-002 \
        bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$RUN_DIR" 2>&1 || true)"
grep -q "MERGE_BLOCKED=true" <<< "$MOUT"

# 仅 batch-001（未纳入 batch-002）→ 阶段性报告标题
MOUT2="$(MERGE_WAIT_TIMEOUT_SECONDS=0 RUN_BATCH_IDS=batch-001 \
         bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$RUN_DIR" || true)"
SUMM="$(printf '%s\n' "$MOUT2" | sed -n 's/^SUMMARY_PATH=//p')"
grep -q '"source_file_coverage_percent"' "$SUMM"
grep -q '"report_title"' "$SUMM"
grep -q '"finding_count": 1' "$SUMM"
REPORT="$(printf '%s\n' "$MOUT2" | sed -n 's/^FINAL_REPORT_PATH=//p')"
head -n1 "$REPORT" | grep -q '\[阶段性\]'

# 两批都 completed 且都纳入 → 完整报告（无 [阶段性] / [合并阻塞]）
cat > "$RUN_DIR/results/batch-002.status.json" <<JSON
{"batch_id":"batch-002","status":"completed","planned_source_loc":250,
 "planned_source_file_count":1,"result_path":"$RUN_DIR/results/batch-002.md","finding_count":0}
JSON
cat > "$RUN_DIR/results/batch-002.md" <<'MD'
# Batch 002
## 发现列表
（无正式发现）
MD
MOUT3="$(MERGE_WAIT_TIMEOUT_SECONDS=0 RUN_BATCH_IDS=batch-001,batch-002 \
         bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$RUN_DIR" 2>&1 || true)"
REPORT3="$(printf '%s\n' "$MOUT3" | sed -n 's/^FINAL_REPORT_PATH=//p')"
head -n1 "$REPORT3" | grep -qv '\[阶段性\]'
head -n1 "$REPORT3" | grep -qv '\[合并阻塞\]'

echo "PASS: core merge-batch-results"
