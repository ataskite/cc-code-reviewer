#!/bin/bash
# 测试：scripts/core/show-batch-status.sh 字段按 language_id 切换 + fallback
# 验证：Java plan（java_* 字段）和前端 plan（source_* 字段）都能渲染状态表，
#       且 Java 输出含「Java 行数」、前端输出含「源码行数」。
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/core/show-batch-status.sh"

make_run() {
  local lang="$1" loc_field="$2" file_field="$3"
  local tmp; tmp="$(mktemp -d)"
  local run_dir="$tmp/.cc-code-reviewer/runs/20260101-000000-main-standard"
  mkdir -p "$run_dir/batches" "$run_dir/results"
  cat > "$run_dir/plan.json" <<EOF
{"language_id":"$lang","batch_count":1,"$loc_field":1500,"$file_field":20,"review_mode":"standard","run_id":"test","project_name":"p","review_scope":"全量"}
EOF
  cat > "$run_dir/batches/batch-001.json" <<EOF
{"batch_id":"batch-001","scan_roots":["src"],"planned_${lang}_loc":1500,"planned_${lang}_file_count":20,"planned_review_cost":1500,"modules":"mod-a"}
EOF
  echo "$tmp"
}

# Java plan（java_* 字段）
JTMP="$(make_run java total_java_loc total_java_file_count)"
JOUT="$(bash "$SCRIPT" "$JTMP")"
echo "$JOUT" | grep -q "batch-001"
echo "$JOUT" | grep -qE "Java 行数|Java 行覆盖"

# 前端 plan（source_* 字段）
FTMP="$(make_run frontend total_source_loc total_source_file_count)"
FOUT="$(bash "$SCRIPT" "$FTMP")"
echo "$FOUT" | grep -q "batch-001"
echo "$FOUT" | grep -qE "源码行数|源码行覆盖"

# Python plan（同样使用 source_* 字段）
PYTMP="$(make_run python total_source_loc total_source_file_count)"
PYOUT="$(bash "$SCRIPT" "$PYTMP")"
echo "$PYOUT" | grep -q "batch-001"
echo "$PYOUT" | grep -qE "Python 行数|Python 行覆盖"

# Java plan.json 缺 language_id 时应 fallback 为 java（旧行为兼容）
JTMP2="$(mktemp -d)"; JRUN2="$JTMP2/.cc-code-reviewer/runs/r2"; mkdir -p "$JRUN2/batches"
cat > "$JRUN2/plan.json" <<'EOF'
{"batch_count":0,"total_java_loc":0,"total_java_file_count":0,"review_mode":"standard","run_id":"r2","project_name":"p","review_scope":"全量"}
EOF
bash "$SCRIPT" "$JTMP2" >/dev/null  # 不应报错

# partial 状态批次：显示「部分完成待重跑」，计入本轮可执行批次（可整批重跑）
PTMP="$(mktemp -d)"
PRUN="$PTMP/.cc-code-reviewer/runs/20260101-000000-main-standard"
mkdir -p "$PRUN/batches" "$PRUN/results"
cat > "$PRUN/plan.json" <<'EOF'
{"language_id":"frontend","batch_count":1,"total_source_loc":1500,"total_source_file_count":20,"review_mode":"standard","run_id":"test","project_name":"p","review_scope":"全量"}
EOF
cat > "$PRUN/batches/batch-001.json" <<'EOF'
{"batch_id":"batch-001","scan_roots":["src"],"planned_source_loc":1500,"planned_source_file_count":20,"planned_review_cost":1500,"modules":[{"name":"mod-a"}]}
EOF
cat > "$PRUN/results/batch-001.status.json" <<'EOF'
{"batch_id":"batch-001","status":"partial","planned_source_loc":1500,"planned_source_file_count":20,"error":"中断"}
EOF
POUT="$(bash "$SCRIPT" "$PTMP")"
echo "$POUT" | grep -q "| batch-001 | 部分完成待重跑 | 1,500 | 20 | mod-a |"
echo "$POUT" | grep -q "本轮可执行批次: batch-001"
echo "$POUT" | grep -q "部分完成待重跑批次可以在本轮调度"
# partial 批次的行数不计入已完成覆盖（保守口径）
echo "$POUT" | grep -q "前端源码行覆盖: 0 / 1,500"

rm -rf "$JTMP" "$FTMP" "$PYTMP" "$JTMP2" "$PTMP"
echo "PASS: core show-batch-status"
