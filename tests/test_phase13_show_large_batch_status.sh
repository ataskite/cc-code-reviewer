#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase13-large.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_DIR="$TMP_DIR/maven-large"
RUN_ID="20260528-010203-main-standard-full-large-maven"
RUN_DIR="$PROJECT_DIR/.cc-code-reviewer/runs/$RUN_ID"
mkdir -p "$RUN_DIR/batches" "$RUN_DIR/results"

cat > "$RUN_DIR/plan.json" <<JSON
{
  "schema_version": 1,
  "run_id": "$RUN_ID",
  "project_name": "maven-large",
  "project_dir": "$PROJECT_DIR",
  "review_mode": "standard",
  "review_scope": "全量代码",
  "semantic_level": "maven-static",
  "total_java_loc": 500000,
  "total_java_file_count": 4000,
  "batch_count": 2
}
JSON

cat > "$RUN_DIR/batches/batch-001.json" <<'JSON'
{
  "schema_version": 1,
  "batch_id": "batch-001",
  "strategy": "semantic-cost-batching",
  "planned_java_loc": 24800,
  "planned_review_cost": 31250,
  "planned_java_file_count": 210,
  "scan_roots": ["user-api", "user-service"],
  "context_roots": ["server/bootstrap"],
  "units": [
    {"name": "user-api", "path": "user-api"},
    {"name": "user-service", "path": "user-service"}
  ],
  "modules": [
    {"name": "user-api", "path": "user-api"},
    {"name": "user-service", "path": "user-service"}
  ],
  "split_reason": "dependency_affinity_group"
}
JSON

cat > "$RUN_DIR/batches/batch-002.json" <<'JSON'
{
  "schema_version": 1,
  "batch_id": "batch-002",
  "strategy": "semantic-cost-batching",
  "planned_java_loc": 25200,
  "planned_review_cost": 31800,
  "planned_java_file_count": 190,
  "scan_roots": ["order-service"],
  "context_roots": ["server/bootstrap"],
  "units": [
    {"name": "order-service", "path": "order-service"}
  ],
  "modules": [
    {"name": "order-service", "path": "order-service"}
  ],
  "split_reason": "dependency_affinity_group"
}
JSON

cat > "$RUN_DIR/results/batch-001.status.json" <<'JSON'
{
  "schema_version": 1,
  "batch_id": "batch-001",
  "status": "completed",
  "planned_java_loc": 24800,
  "planned_java_file_count": 210
}
JSON

cat > "$RUN_DIR/results/batch-002.status.json" <<'JSON'
{
  "schema_version": 1,
  "batch_id": "batch-002",
  "status": "failed",
  "planned_java_loc": 25200,
  "planned_java_file_count": 190,
  "error": "review failed"
}
JSON

OUTPUT="$(bash "$ROOT_DIR/scripts/phase13-show-large-batch-status.sh" "$PROJECT_DIR")"

printf '%s\n' "$OUTPUT" | grep -q "大仓库审查任务"
printf '%s\n' "$OUTPUT" | grep -q "批次 状态 行数 成本 文件 模块 原因"
printf '%s\n' "$OUTPUT" | grep -q "已完成"
printf '%s\n' "$OUTPUT" | grep -q "失败待重试"
printf '%s\n' "$OUTPUT" | grep -q "user-api,user-service"
printf '%s\n' "$OUTPUT" | grep -q "dependency_affinity_group"
printf '%s\n' "$OUTPUT" | grep -q "context:server/bootstrap"
printf '%s\n' "$OUTPUT" | grep -q "Java 行覆盖: 24,800 / 500,000"
printf '%s\n' "$OUTPUT" | grep -q "本轮可执行批次"
printf '%s\n' "$OUTPUT" | grep -q "batch-002"
printf '%s\n' "$OUTPUT" | grep -q "推荐执行计划"
printf '%s\n' "$OUTPUT" | grep -q "执行 5 批（推荐）"
printf '%s\n' "$OUTPUT" | grep -q "预估耗时"
printf '%s\n' "$OUTPUT" | grep -q "也可以自行输入批次号"

if printf '%s\n' "$OUTPUT" | grep -qE '(^|[[:space:]])(pending|running|completed|failed)([[:space:]]|$)'; then
  echo "status output must not expose internal enum values" >&2
  printf '%s\n' "$OUTPUT" >&2
  exit 1
fi

echo "PASS: phase13 large Maven batch status"
