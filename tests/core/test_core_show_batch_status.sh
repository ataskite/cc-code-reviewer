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

# Java plan.json 缺 language_id 时应 fallback 为 java（旧行为兼容）
JTMP2="$(mktemp -d)"; JRUN2="$JTMP2/.cc-code-reviewer/runs/r2"; mkdir -p "$JRUN2/batches"
cat > "$JRUN2/plan.json" <<'EOF'
{"batch_count":0,"total_java_loc":0,"total_java_file_count":0,"review_mode":"standard","run_id":"r2","project_name":"p","review_scope":"全量"}
EOF
bash "$SCRIPT" "$JTMP2" >/dev/null  # 不应报错

rm -rf "$JTMP" "$FTMP" "$JTMP2"
echo "PASS: core show-batch-status"
