#!/bin/bash
# 测试：core/merge-batch-results.sh 兼容 Java 旧 plan.json 的 java_* 字段名
# 验证：plan.json 用 total_java_loc（而非 source_*）时，merge 仍能正确读取并生成覆盖率字段。
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
RUN_DIR="$TMP/.cc-code-reviewer/runs/20260101-000000-main-standard"
mkdir -p "$RUN_DIR/batches" "$RUN_DIR/results"
cat > "$RUN_DIR/plan.json" <<'EOF'
{"language_id":"java","batch_count":1,"total_java_loc":1000,"total_java_file_count":10,"review_mode":"standard","run_id":"test","project_name":"p","review_scope":"全量"}
EOF
cat > "$RUN_DIR/batches/batch-001.json" <<'EOF'
{"batch_id":"batch-001","scan_roots":["src"],"planned_java_loc":1000,"planned_java_file_count":10,"planned_review_cost":1000,"modules":"m"}
EOF
cat > "$RUN_DIR/results/batch-001.status.json" <<'EOF'
{"status":"completed","planned_java_loc":1000,"planned_java_file_count":10}
EOF
echo "## 审查发现" > "$RUN_DIR/results/batch-001.findings.md"

MERGE_WAIT_TIMEOUT_SECONDS=0 bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$RUN_DIR" >/dev/null 2>&1 || true
[ -f "$RUN_DIR/summary.json" ] || { echo "FAIL: summary.json 未生成" >&2; exit 1; }
# 覆盖率字段至少一个存在（字段名可能是 java_loc_coverage_percent 或 source_file_coverage_percent）
grep -qE '"(java_loc_coverage_percent|java_file_coverage_percent|source_file_coverage_percent|source_loc_coverage_percent)"' "$RUN_DIR/summary.json" || \
  { echo "FAIL: 覆盖率字段缺失" >&2; exit 1; }
# 关键：TOTAL_LOC 必须从 java_* 字段正确读到 1000，写出为 total_source_loc（证明 fallback 生效）
grep -q '"total_source_loc": 1000' "$RUN_DIR/summary.json" || \
  { echo "FAIL: total_source_loc 应为 1000（从 java_* fallback 读到），实际:" >&2; grep total_source_loc "$RUN_DIR/summary.json" >&2; exit 1; }
rm -rf "$TMP"
echo "PASS: core merge java fields"
