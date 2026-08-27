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
# 无显式 failure_class → 失败归因行必须省略
if echo "$POUT" | grep -q "失败归因"; then
  echo "FAIL: 无 failure_class 时不得输出失败归因行" >&2
  exit 1
fi

# 显式 failure_class（封闭枚举）→ 失败归因行按中文短标签计数，顺序按枚举序固定；
# 并按出现类别输出重试提示（工具预算耗尽/输出中断可直接重试；上下文耗尽建议拆批）。
CTMP="$(mktemp -d)"
CRUN="$CTMP/.cc-code-reviewer/runs/20260101-000000-main-standard"
mkdir -p "$CRUN/batches" "$CRUN/results"
cat > "$CRUN/plan.json" <<'EOF'
{"language_id":"frontend","batch_count":3,"total_source_loc":3000,"total_source_file_count":30,"review_mode":"standard","run_id":"test","project_name":"p","review_scope":"全量"}
EOF
cat > "$CRUN/batches/batch-001.json" <<'EOF'
{"batch_id":"batch-001","scan_roots":["src"],"planned_source_loc":1000,"planned_source_file_count":10,"planned_review_cost":1000,"modules":[{"name":"mod-a"}]}
EOF
cat > "$CRUN/batches/batch-002.json" <<'EOF'
{"batch_id":"batch-002","scan_roots":["web"],"planned_source_loc":1000,"planned_source_file_count":10,"planned_review_cost":1000,"modules":[{"name":"mod-b"}]}
EOF
cat > "$CRUN/batches/batch-003.json" <<'EOF'
{"batch_id":"batch-003","scan_roots":["api"],"planned_source_loc":1000,"planned_source_file_count":10,"planned_review_cost":1000,"modules":[{"name":"mod-c"}]}
EOF
cat > "$CRUN/results/batch-001.status.json" <<'EOF'
{"batch_id":"batch-001","status":"failed","failure_class":"context_exhausted","error":"上下文不足以完成整批"}
EOF
cat > "$CRUN/results/batch-002.status.json" <<'EOF'
{"batch_id":"batch-002","status":"failed","failure_class":"tool_budget_exhausted","error":"工具调用轮次预算耗尽"}
EOF
cat > "$CRUN/results/batch-003.status.json" <<'EOF'
{"batch_id":"batch-003","status":"partial","failure_class":"context_exhausted","error":"上下文耗尽，已产出部分发现"}
EOF
COUT="$(bash "$SCRIPT" "$CTMP")"
echo "$COUT" | grep -qF "失败归因: 上下文耗尽 ×2、工具预算耗尽 ×1"
if printf '%s\n' "$COUT" | grep -qE '(^|[[:space:]])(context_exhausted|tool_budget_exhausted|output_truncated|cancelled|unknown)([[:space:]]|$)'; then
  echo "FAIL: 失败归因只允许中文短标签，不允许英文枚举词泄漏" >&2
  exit 1
fi
echo "$COUT" | grep -qF "重试提示: 工具预算耗尽、输出中断的批次可直接原样重试。"
echo "$COUT" | grep -qF "重试提示: 上下文耗尽的批次建议拆批或缩小范围后重跑。"
if printf '%s\n' "$COUT" | grep -qF "重试提示: 已取消的批次请先人工确认原因"; then
  echo "FAIL: 未出现已取消类时不得输出其重试提示" >&2
  exit 1
fi

# 显式 unknown 属于封闭枚举 → 归因行计「未知」，但不给任何重试提示（中性兜底）。
UTMP="$(mktemp -d)"
URUN="$UTMP/.cc-code-reviewer/runs/20260101-000000-main-standard"
mkdir -p "$URUN/batches" "$URUN/results"
cp "$CRUN/plan.json" "$URUN/plan.json"
cp "$CRUN/batches/batch-001.json" "$URUN/batches/"
cat > "$URUN/results/batch-001.status.json" <<'EOF'
{"batch_id":"batch-001","status":"failed","failure_class":"unknown","error":"subagent failed"}
EOF
UOUT="$(bash "$SCRIPT" "$UTMP")"
echo "$UOUT" | grep -qF "失败归因: 未知 ×1"
if printf '%s\n' "$UOUT" | grep -qF "重试提示:"; then
  echo "FAIL: unknown 归因必须保持中性，不得输出重试提示" >&2
  exit 1
fi

# 已取消类：归因行计数 + 人工确认提示；不误触其他两类提示。
XTMP="$(mktemp -d)"
XRUN="$XTMP/.cc-code-reviewer/runs/20260101-000000-main-standard"
mkdir -p "$XRUN/batches" "$XRUN/results"
cp "$CRUN/plan.json" "$XRUN/plan.json"
cp "$CRUN/batches/batch-001.json" "$XRUN/batches/"
cp "$CRUN/batches/batch-002.json" "$XRUN/batches/"
cat > "$XRUN/results/batch-001.status.json" <<'EOF'
{"batch_id":"batch-001","status":"failed","failure_class":"cancelled","error":"用户在宿主侧中止"}
EOF
cat > "$XRUN/results/batch-002.status.json" <<'EOF'
{"batch_id":"batch-002","status":"partial","failure_class":"context_exhausted","error":"上下文耗尽，已产出部分发现"}
EOF
XOUT="$(bash "$SCRIPT" "$XTMP")"
echo "$XOUT" | grep -qF "失败归因: 上下文耗尽 ×1、已取消 ×1"
echo "$XOUT" | grep -qF "重试提示: 上下文耗尽的批次建议拆批或缩小范围后重跑。"
echo "$XOUT" | grep -qF "重试提示: 已取消的批次请先人工确认原因，再决定是否整批重跑。"
if printf '%s\n' "$XOUT" | grep -qF "重试提示: 工具预算耗尽、输出中断的批次可直接原样重试。"; then
  echo "FAIL: 未出现工具预算/输出中断类时不得输出可直接重试提示" >&2
  exit 1
fi

# 输出中断类单独触发「可直接原样重试」提示。
TTMP="$(mktemp -d)"
TRUN="$TTMP/.cc-code-reviewer/runs/20260101-000000-main-standard"
mkdir -p "$TRUN/batches" "$TRUN/results"
cp "$CRUN/plan.json" "$TRUN/plan.json"
cp "$CRUN/batches/batch-001.json" "$TRUN/batches/"
cat > "$TRUN/results/batch-001.status.json" <<'EOF'
{"batch_id":"batch-001","status":"failed","failure_class":"output_truncated","error":"发现清单写入中途断掉"}
EOF
TOUT="$(bash "$SCRIPT" "$TTMP")"
echo "$TOUT" | grep -qF "失败归因: 输出中断 ×1"
echo "$TOUT" | grep -qF "重试提示: 工具预算耗尽、输出中断的批次可直接原样重试。"
if printf '%s\n' "$TOUT" | grep -qE "重试提示: (上下文耗尽|已取消的批次)"; then
  echo "FAIL: 仅输出中断类时不得输出拆批/人工确认提示" >&2
  exit 1
fi

# 枚举外值不计数：整轮无 canonical 归因 → 行省略
IVTMP="$(mktemp -d)"
IVRUN="$IVTMP/.cc-code-reviewer/runs/20260101-000000-main-standard"
mkdir -p "$IVRUN/batches" "$IVRUN/results"
cp "$CRUN/plan.json" "$IVRUN/plan.json"
cp "$CRUN/batches/batch-001.json" "$IVRUN/batches/"
cat > "$IVRUN/results/batch-001.status.json" <<'EOF'
{"batch_id":"batch-001","status":"failed","failure_class":"server_overload","error":"review timed out"}
EOF
IVOUT="$(bash "$SCRIPT" "$IVTMP")"
if echo "$IVOUT" | grep -q "失败归因"; then
  echo "FAIL: 枚举外 failure_class 不计入失败归因" >&2
  exit 1
fi
if echo "$IVOUT" | grep -q "重试提示:"; then
  echo "FAIL: 无可归类失败时不得输出重试提示" >&2
  exit 1
fi

rm -rf "$JTMP" "$FTMP" "$PYTMP" "$JTMP2" "$PTMP" "$CTMP" "$UTMP" "$XTMP" "$TTMP" "$IVTMP"
echo "PASS: core show-batch-status"
