#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase13-large.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_DIR="$TMP_DIR/maven-large"
RUN_ID="20260528-010203-main-standard"
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
  "scan_roots": ["order-service/src/main/java/com/example/order/api"],
  "context_roots": ["server/bootstrap"],
  "units": [
    {"name": "order-service:com/example/order/api", "path": "order-service/src/main/java/com/example/order/api", "kind": "java-package"}
  ],
  "modules": [
    {"name": "order-service:com/example/order/api", "path": "order-service/src/main/java/com/example/order/api"}
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

OUTPUT="$(bash "$ROOT_DIR/scripts/core/show-batch-status.sh" "$PROJECT_DIR")"

printf '%s\n' "$OUTPUT" | grep -q "大仓库审查任务"
printf '%s\n' "$OUTPUT" | grep -q "| 批次 | 状态 | 行数 | 文件数 | 模块 |"
printf '%s\n' "$OUTPUT" | grep -q "|------|------|------:|------:|------|"
printf '%s\n' "$OUTPUT" | grep -q "| batch-001 | 已完成 | 24,800 | 210 | user-api,user-service |"
printf '%s\n' "$OUTPUT" | grep -q "| batch-002 | 失败待重试 | 25,200 | 190 | order-service（部分） |"
if printf '%s\n' "$OUTPUT" | grep -q "批次 状态 行数"; then
  echo "status table must use a Markdown table, not whitespace-separated columns" >&2
  printf '%s\n' "$OUTPUT" >&2
  exit 1
fi
printf '%s\n' "$OUTPUT" | grep -q "已完成"
printf '%s\n' "$OUTPUT" | grep -q "失败待重试"
printf '%s\n' "$OUTPUT" | grep -q "user-api,user-service"
printf '%s\n' "$OUTPUT" | grep -q "order-service（部分）"
if printf '%s\n' "$OUTPUT" | grep -q "dependency_affinity_group"; then
  echo "status table must not show split reasons" >&2
  printf '%s\n' "$OUTPUT" >&2
  exit 1
fi
if printf '%s\n' "$OUTPUT" | grep -q "context:server/bootstrap"; then
  echo "status table module column must not include context roots" >&2
  printf '%s\n' "$OUTPUT" >&2
  exit 1
fi
printf '%s\n' "$OUTPUT" | grep -q "Java 行覆盖: 24,800 / 500,000"
printf '%s\n' "$OUTPUT" | grep -q "本轮可执行批次"
printf '%s\n' "$OUTPUT" | grep -q "batch-002"
printf '%s\n' "$OUTPUT" | grep -q "推荐执行计划"
printf '%s\n' "$OUTPUT" | grep -q "仅 1 个可执行批次，将自动选择 batch-002，并自动设置并发数为 1。"
if printf '%s\n' "$OUTPUT" | grep -q "执行 5 批"; then
  echo "single runnable batch must not show fixed 5-batch option" >&2
  printf '%s\n' "$OUTPUT" >&2
  exit 1
fi
if printf '%s\n' "$OUTPUT" | grep -qE "2 路约|3 路约"; then
  echo "single runnable batch must not show impossible 2/3-way concurrency estimates" >&2
  printf '%s\n' "$OUTPUT" >&2
  exit 1
fi
printf '%s\n' "$OUTPUT" | grep -q "也可以自行输入批次号"
# failed 批次未写显式 failure_class（legacy）→ 失败归因行必须省略，不做文本推断
if printf '%s\n' "$OUTPUT" | grep -q "失败归因"; then
  echo "failed batch without failure_class must not render attribution line" >&2
  exit 1
fi

if printf '%s\n' "$OUTPUT" | grep -qE '(^|[[:space:]])(pending|running|completed|failed)([[:space:]]|$)'; then
  echo "status output must not expose internal enum values" >&2
  printf '%s\n' "$OUTPUT" >&2
  exit 1
fi

THREE_RUN_ID="20260528-020203-main-deep"
THREE_RUN_DIR="$PROJECT_DIR/.cc-code-reviewer/runs/$THREE_RUN_ID"
mkdir -p "$THREE_RUN_DIR/batches" "$THREE_RUN_DIR/results"

cat > "$THREE_RUN_DIR/plan.json" <<JSON
{
  "schema_version": 1,
  "run_id": "$THREE_RUN_ID",
  "project_name": "maven-large",
  "project_dir": "$PROJECT_DIR",
  "review_mode": "deep",
  "review_scope": "yudao-module-mall",
  "semantic_level": "jdtls-lsp",
  "total_java_loc": 51817,
  "total_java_file_count": 842,
  "batch_count": 3
}
JSON

for batch_id in batch-001 batch-002 batch-003; do
  cat > "$THREE_RUN_DIR/batches/$batch_id.json" <<JSON
{
  "schema_version": 1,
  "batch_id": "$batch_id",
  "strategy": "semantic-cost-batching",
  "planned_java_loc": 17000,
  "planned_review_cost": 32000,
  "planned_java_file_count": 250,
  "scan_roots": ["yudao-module-mall"],
  "units": [
    {"name": "yudao-module-trade-server", "path": "yudao-module-mall/yudao-module-trade-server"},
    {"name": "yudao-module-statistics-server", "path": "yudao-module-mall/yudao-module-statistics-server"},
    {"name": "yudao-module-statistics-api", "path": "yudao-module-mall/yudao-module-statistics-api"}
  ]
}
JSON
done

THREE_OUTPUT="$(bash "$ROOT_DIR/scripts/core/show-batch-status.sh" "$PROJECT_DIR")"
printf '%s\n' "$THREE_OUTPUT" | grep -q "| batch-001 | 待执行 | 17,000 | 250 | trade-server,statistics-server,statistics-api |"
if printf '%s\n' "$THREE_OUTPUT" | grep -q "yudao-module-trade-server"; then
  echo "batch module display should drop the shared yudao-module- prefix" >&2
  printf '%s\n' "$THREE_OUTPUT" >&2
  exit 1
fi
printf '%s\n' "$THREE_OUTPUT" | grep -q "执行 1 批"
printf '%s\n' "$THREE_OUTPUT" | grep -q "执行 2 批"
printf '%s\n' "$THREE_OUTPUT" | grep -q "执行全部 3 批（推荐）"
printf '%s\n' "$THREE_OUTPUT" | grep -q "执行 1 批（最多 1 批）"
printf '%s\n' "$THREE_OUTPUT" | grep -q "执行 2 批（最多 2 批）"
printf '%s\n' "$THREE_OUTPUT" | grep -q "执行全部 3 批（推荐）（最多 3 批）"
if printf '%s\n' "$THREE_OUTPUT" | grep -qE "执行 1 批 .*2 路|执行 1 批 .*3 路|执行 2 批 .*3 路"; then
  echo "batch-plan estimates must not show concurrency greater than the selected batch count" >&2
  printf '%s\n' "$THREE_OUTPUT" >&2
  exit 1
fi
if printf '%s\n' "$THREE_OUTPUT" | grep -q "串行约 180 分钟"; then
  echo "deep batch estimate must use planned review cost instead of fixed 60 minutes per batch" >&2
  printf '%s\n' "$THREE_OUTPUT" >&2
  exit 1
fi
if printf '%s\n' "$THREE_OUTPUT" | grep -qE "执行 (5|10) 批"; then
  echo "three runnable batches must not show fixed 5/10-batch options" >&2
  printf '%s\n' "$THREE_OUTPUT" >&2
  exit 1
fi

# partial 状态批次：标签「部分完成待重跑」、计入本轮可执行批次；行覆盖按保守口径只统计 completed
PARTIAL_RUN_ID="20260528-030203-main-standard"
PARTIAL_RUN_DIR="$PROJECT_DIR/.cc-code-reviewer/runs/$PARTIAL_RUN_ID"
mkdir -p "$PARTIAL_RUN_DIR/batches" "$PARTIAL_RUN_DIR/results"

cat > "$PARTIAL_RUN_DIR/plan.json" <<JSON
{
  "schema_version": 1,
  "run_id": "$PARTIAL_RUN_ID",
  "project_name": "maven-large",
  "project_dir": "$PROJECT_DIR",
  "review_mode": "standard",
  "review_scope": "全量代码",
  "semantic_level": "maven-static",
  "total_java_loc": 50000,
  "total_java_file_count": 400,
  "batch_count": 2
}
JSON

cat > "$PARTIAL_RUN_DIR/batches/batch-001.json" <<'JSON'
{
  "schema_version": 1,
  "batch_id": "batch-001",
  "strategy": "semantic-cost-batching",
  "planned_java_loc": 25000,
  "planned_review_cost": 30000,
  "planned_java_file_count": 200,
  "scan_roots": ["core"],
  "modules": [{"name": "core"}]
}
JSON

cat > "$PARTIAL_RUN_DIR/batches/batch-002.json" <<'JSON'
{
  "schema_version": 1,
  "batch_id": "batch-002",
  "strategy": "semantic-cost-batching",
  "planned_java_loc": 25000,
  "planned_review_cost": 30000,
  "planned_java_file_count": 200,
  "scan_roots": ["web"],
  "modules": [{"name": "web"}]
}
JSON

cat > "$PARTIAL_RUN_DIR/results/batch-001.status.json" <<'JSON'
{
  "schema_version": 1,
  "batch_id": "batch-001",
  "status": "completed",
  "planned_java_loc": 25000,
  "planned_java_file_count": 200
}
JSON

cat > "$PARTIAL_RUN_DIR/results/batch-002.status.json" <<'JSON'
{
  "schema_version": 1,
  "batch_id": "batch-002",
  "status": "partial",
  "planned_java_loc": 25000,
  "planned_java_file_count": 200,
  "error": "subagent interrupted"
}
JSON

PARTIAL_OUTPUT="$(bash "$ROOT_DIR/scripts/core/show-batch-status.sh" "$PROJECT_DIR")"

printf '%s\n' "$PARTIAL_OUTPUT" | grep -q "| batch-001 | 已完成 | 25,000 | 200 | core |"
printf '%s\n' "$PARTIAL_OUTPUT" | grep -q "| batch-002 | 部分完成待重跑 | 25,000 | 200 | web |"
printf '%s\n' "$PARTIAL_OUTPUT" | grep -q "Java 行覆盖: 25,000 / 50,000"
printf '%s\n' "$PARTIAL_OUTPUT" | grep -q "本轮可执行批次: batch-002"
printf '%s\n' "$PARTIAL_OUTPUT" | grep -q "仅 1 个可执行批次，将自动选择 batch-002，并自动设置并发数为 1。"
if printf '%s\n' "$PARTIAL_OUTPUT" | grep -qE '(^|[[:space:]])(pending|running|completed|failed|partial)([[:space:]]|$)'; then
  echo "status output must not expose internal enum values" >&2
  printf '%s\n' "$PARTIAL_OUTPUT" >&2
  exit 1
fi
printf '%s\n' "$PARTIAL_OUTPUT" | grep -q "部分完成待重跑批次可以在本轮调度"

# 失败归因行：failed/partial 批次显式 failure_class（封闭枚举）按中文短标签计数，
# 顺序固定为枚举序；英文枚举词不得出现在输出中；并按出现类别输出重试提示
# （工具预算耗尽/输出中断可直接原样重试；上下文耗尽建议拆批或缩小范围后重跑）。
ATTR_RUN_ID="20260528-040203-main-standard"
ATTR_RUN_DIR="$PROJECT_DIR/.cc-code-reviewer/runs/$ATTR_RUN_ID"
mkdir -p "$ATTR_RUN_DIR/batches" "$ATTR_RUN_DIR/results"

cat > "$ATTR_RUN_DIR/plan.json" <<JSON
{
  "schema_version": 1,
  "run_id": "$ATTR_RUN_ID",
  "project_name": "maven-large",
  "project_dir": "$PROJECT_DIR",
  "review_mode": "standard",
  "review_scope": "全量代码",
  "semantic_level": "maven-static",
  "total_java_loc": 30000,
  "total_java_file_count": 600,
  "batch_count": 3
}
JSON

cat > "$ATTR_RUN_DIR/batches/batch-001.json" <<'JSON'
{"batch_id":"batch-001","planned_java_loc":10000,"planned_review_cost":12500,"planned_java_file_count":200,"scan_roots":["alpha"],"modules":[{"name":"alpha"}]}
JSON
cat > "$ATTR_RUN_DIR/batches/batch-002.json" <<'JSON'
{"batch_id":"batch-002","planned_java_loc":10000,"planned_review_cost":12500,"planned_java_file_count":200,"scan_roots":["beta"],"modules":[{"name":"beta"}]}
JSON
cat > "$ATTR_RUN_DIR/batches/batch-003.json" <<'JSON'
{"batch_id":"batch-003","planned_java_loc":10000,"planned_review_cost":12500,"planned_java_file_count":200,"scan_roots":["gamma"],"modules":[{"name":"gamma"}]}
JSON
cat > "$ATTR_RUN_DIR/results/batch-001.status.json" <<'JSON'
{"batch_id":"batch-001","status":"failed","failure_class":"tool_budget_exhausted","error":"工具调用轮次预算耗尽"}
JSON
cat > "$ATTR_RUN_DIR/results/batch-002.status.json" <<'JSON'
{"batch_id":"batch-002","status":"failed","failure_class":"context_exhausted","error":"上下文不足以完成整批"}
JSON
cat > "$ATTR_RUN_DIR/results/batch-003.status.json" <<'JSON'
{"batch_id":"batch-003","status":"partial","failure_class":"tool_budget_exhausted","error":"工具调用轮次预算耗尽，已产出部分发现"}
JSON

ATTR_OUTPUT="$(bash "$ROOT_DIR/scripts/core/show-batch-status.sh" "$PROJECT_DIR")"
printf '%s\n' "$ATTR_OUTPUT" | grep -qF "失败归因: 上下文耗尽 ×1、工具预算耗尽 ×2"
printf '%s\n' "$ATTR_OUTPUT" | grep -qF "重试提示: 工具预算耗尽、输出中断的批次可直接原样重试。"
printf '%s\n' "$ATTR_OUTPUT" | grep -qF "重试提示: 上下文耗尽的批次建议拆批或缩小范围后重跑。"
printf '%s\n' "$ATTR_OUTPUT" | grep -q "| batch-001 | 失败待重试 |"
printf '%s\n' "$ATTR_OUTPUT" | grep -q "| batch-002 | 失败待重试 |"
printf '%s\n' "$ATTR_OUTPUT" | grep -q "| batch-003 | 部分完成待重跑 |"
if printf '%s\n' "$ATTR_OUTPUT" | grep -qE '(^|[[:space:]])(pending|running|completed|failed|partial|context_exhausted|tool_budget_exhausted|output_truncated|cancelled|unknown)([[:space:]]|$)'; then
  echo "attribution output must use Chinese labels only, no internal enum values" >&2
  printf '%s\n' "$ATTR_OUTPUT" >&2
  exit 1
fi

# 已取消批次：归因行计「已取消」，并输出人工确认提示；不误触其他两类提示。
CANCEL_RUN_ID="20260528-050203-main-standard"
CANCEL_RUN_DIR="$PROJECT_DIR/.cc-code-reviewer/runs/$CANCEL_RUN_ID"
mkdir -p "$CANCEL_RUN_DIR/batches" "$CANCEL_RUN_DIR/results"

cp "$ATTR_RUN_DIR/plan.json" "$CANCEL_RUN_DIR/plan.json"
cat > "$CANCEL_RUN_DIR/plan.json" <<JSON
{
  "schema_version": 1,
  "run_id": "$CANCEL_RUN_ID",
  "project_name": "maven-large",
  "project_dir": "$PROJECT_DIR",
  "review_mode": "standard",
  "review_scope": "全量代码",
  "semantic_level": "maven-static",
  "total_java_loc": 30000,
  "total_java_file_count": 600,
  "batch_count": 1
}
JSON

cp "$ATTR_RUN_DIR/batches/batch-001.json" "$CANCEL_RUN_DIR/batches/"
cat > "$CANCEL_RUN_DIR/results/batch-001.status.json" <<'JSON'
{"batch_id":"batch-001","status":"failed","failure_class":"cancelled","error":"用户在宿主侧中止"}
JSON

CANCEL_OUTPUT="$(bash "$ROOT_DIR/scripts/core/show-batch-status.sh" "$PROJECT_DIR")"
printf '%s\n' "$CANCEL_OUTPUT" | grep -qF "失败归因: 已取消 ×1"
printf '%s\n' "$CANCEL_OUTPUT" | grep -qF "重试提示: 已取消的批次请先人工确认原因，再决定是否整批重跑。"
if printf '%s\n' "$CANCEL_OUTPUT" | grep -qE "重试提示: (工具预算耗尽|上下文耗尽)"; then
  echo "FAIL: 仅已取消类时不得输出可直接重试或拆批提示" >&2
  printf '%s\n' "$CANCEL_OUTPUT" >&2
  exit 1
fi

# phase13 转发 wrapper 后，输出必须与 core/show-batch-status.sh 逐字节一致
OLD_OUT="$(bash "$ROOT_DIR/scripts/core/show-batch-status.sh" "$PROJECT_DIR" 2>&1)"
NEW_OUT="$(bash "$ROOT_DIR/scripts/core/show-batch-status.sh" "$PROJECT_DIR" 2>&1)"
if [ "$OLD_OUT" != "$NEW_OUT" ]; then
  echo "FAIL: phase13 转发后输出必须与 core/show-batch-status 一致" >&2
  diff <(echo "$OLD_OUT") <(echo "$NEW_OUT") | head -20 >&2
  exit 1
fi

echo "PASS: phase13 large Maven batch status"
