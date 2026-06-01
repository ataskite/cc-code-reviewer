#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"
RUNS_ROOT="$PROJECT_DIR/.cc-code-reviewer/runs"

json_get() {
  local file="$1"
  local key="$2"
  perl -MJSON::PP -e '
    binmode STDOUT, ":utf8";
    my ($file, $key) = @ARGV;
    open my $fh, "<", $file or exit 0;
    local $/;
    my $data = decode_json(<$fh>);
    my $value = $data->{$key};
    print defined($value) ? $value : "";
  ' "$file" "$key"
}

batch_modules() {
  local file="$1"
  perl -MJSON::PP -e '
    binmode STDOUT, ":utf8";
    my ($file) = @ARGV;
    open my $fh, "<", $file or exit 0;
    local $/;
    my $data = decode_json(<$fh>);
    my @modules;
    if (ref($data->{units}) eq "ARRAY") {
      for my $unit (@{$data->{units}}) {
        if (ref($unit) eq "HASH") {
          push @modules, $unit->{name} // $unit->{path} if defined($unit->{name}) || defined($unit->{path});
        } elsif (defined $unit) {
          push @modules, $unit;
        }
      }
    }
    if (!@modules && ref($data->{modules}) eq "ARRAY") {
      for my $module (@{$data->{modules}}) {
        if (ref($module) eq "HASH") {
          push @modules, $module->{name} // $module->{path} if defined($module->{name}) || defined($module->{path});
        } elsif (defined $module) {
          push @modules, $module;
        }
      }
    }
    if (!@modules && ref($data->{scan_roots}) eq "ARRAY") {
      @modules = @{$data->{scan_roots}};
    }
    print join(",", @modules);
  ' "$file"
}

batch_context_roots() {
  local file="$1"
  perl -MJSON::PP -e '
    binmode STDOUT, ":utf8";
    my ($file) = @ARGV;
    open my $fh, "<", $file or exit 0;
    local $/;
    my $data = decode_json(<$fh>);
    if (ref($data->{context_roots}) eq "ARRAY") {
      print join(",", @{$data->{context_roots}});
    }
  ' "$file"
}

format_number() {
  local value="${1:-0}"
  if [ -z "$value" ]; then
    value=0
  fi
  perl -e '
    my $n = shift;
    $n = 0 if !defined($n) || $n eq "";
    1 while $n =~ s/^(-?\d+)(\d{3})/$1,$2/;
    print $n;
  ' "$value"
}

status_label() {
  case "${1:-pending}" in
    pending) echo "待执行" ;;
    running) echo "执行中" ;;
    completed) echo "已完成" ;;
    failed) echo "失败待重试" ;;
    *) echo "待执行" ;;
  esac
}

ceil_div() {
  local numerator="${1:-0}"
  local denominator="${2:-1}"
  if [ "$denominator" -le 0 ]; then
    denominator=1
  fi
  echo $(((numerator + denominator - 1) / denominator))
}

per_batch_minutes() {
  case "${1:-standard}" in
    fast) echo 8 ;;
    deep) echo 60 ;;
    security) echo 35 ;;
    *) echo 25 ;;
  esac
}

estimate_minutes() {
  local batch_limit="$1"
  local concurrency="$2"
  local minutes_per_batch="$3"
  local rounds
  rounds="$(ceil_div "$batch_limit" "$concurrency")"
  echo $((rounds * minutes_per_batch))
}

display_plan_row() {
  local label="$1"
  local batch_limit="$2"
  local minutes_per_batch="$3"
  local runnable_count="$4"
  local effective_limit="$batch_limit"
  if [ "$effective_limit" -gt "$runnable_count" ]; then
    effective_limit="$runnable_count"
  fi
  if [ "$effective_limit" -lt 1 ]; then
    effective_limit=0
  fi
  printf '%s 最多 %s 批 预估耗时: 串行约 %s 分钟 / 2 路约 %s 分钟 / 3 路约 %s 分钟\n' \
    "$label" \
    "$effective_limit" \
    "$(estimate_minutes "$effective_limit" 1 "$minutes_per_batch")" \
    "$(estimate_minutes "$effective_limit" 2 "$minutes_per_batch")" \
    "$(estimate_minutes "$effective_limit" 3 "$minutes_per_batch")"
}

if [ ! -d "$RUNS_ROOT" ]; then
  echo "未找到大仓库审查任务：$PROJECT_DIR"
  exit 1
fi

RUN_DIR="$(find "$RUNS_ROOT" -maxdepth 1 -type d -name '*-large-maven' -print 2>/dev/null | sort | tail -n 1)"
if [ -z "$RUN_DIR" ] || [ ! -f "$RUN_DIR/plan.json" ]; then
  echo "未找到大仓库审查任务：$PROJECT_DIR"
  exit 1
fi

PLAN_PATH="$RUN_DIR/plan.json"
PROJECT_NAME="$(json_get "$PLAN_PATH" project_name)"
REVIEW_MODE="$(json_get "$PLAN_PATH" review_mode)"
REVIEW_SCOPE="$(json_get "$PLAN_PATH" review_scope)"
SEMANTIC_LEVEL="$(json_get "$PLAN_PATH" semantic_level)"
TOTAL_JAVA_LOC="$(json_get "$PLAN_PATH" total_java_loc)"
TOTAL_JAVA_FILE_COUNT="$(json_get "$PLAN_PATH" total_java_file_count)"
BATCH_COUNT="$(json_get "$PLAN_PATH" batch_count)"

echo "大仓库审查任务"
echo "项目: ${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
echo "模式: ${REVIEW_MODE:-unknown}  范围: ${REVIEW_SCOPE:-全量代码}  语义: ${SEMANTIC_LEVEL:-maven-static}"
echo "批次数: ${BATCH_COUNT:-0}  Java 行数: $(format_number "$TOTAL_JAVA_LOC")  Java 文件: $(format_number "$TOTAL_JAVA_FILE_COUNT")"
echo
echo "批次 状态 行数 成本 文件 模块 原因"

COMPLETED_LOC=0
RUNNABLE_BATCHES=()
for batch_path in "$RUN_DIR"/batches/batch-*.json; do
  [ -f "$batch_path" ] || continue
  batch_id="$(json_get "$batch_path" batch_id)"
  if [ -z "$batch_id" ]; then
    batch_id="$(basename "$batch_path" .json)"
  fi

  status_path="$RUN_DIR/results/$batch_id.status.json"
  status="pending"
  planned_loc="$(json_get "$batch_path" planned_java_loc)"
  planned_files="$(json_get "$batch_path" planned_java_file_count)"
  planned_cost="$(json_get "$batch_path" planned_review_cost)"
  split_reason="$(json_get "$batch_path" split_reason)"
  if [ -f "$status_path" ]; then
    status="$(json_get "$status_path" status)"
    status_loc="$(json_get "$status_path" planned_java_loc)"
    status_files="$(json_get "$status_path" planned_java_file_count)"
    status_cost="$(json_get "$status_path" planned_review_cost)"
    if [ -n "$status_loc" ]; then
      planned_loc="$status_loc"
    fi
    if [ -n "$status_files" ]; then
      planned_files="$status_files"
    fi
    if [ -n "$status_cost" ]; then
      planned_cost="$status_cost"
    fi
  fi
  planned_loc="${planned_loc:-0}"
  planned_files="${planned_files:-0}"
  planned_cost="${planned_cost:-0}"
  split_reason="${split_reason:-unknown}"
  modules="$(batch_modules "$batch_path")"
  contexts="$(batch_context_roots "$batch_path")"
  if [ -n "$contexts" ]; then
    modules="$modules context:$contexts"
  fi

  if [ "$status" = "completed" ]; then
    COMPLETED_LOC=$((COMPLETED_LOC + planned_loc))
  fi
  if [ "$status" = "pending" ] || [ "$status" = "failed" ]; then
    RUNNABLE_BATCHES+=("$batch_id")
  fi

  printf '%s %s %s %s %s %s %s\n' \
    "$batch_id" \
    "$(status_label "$status")" \
    "$(format_number "$planned_loc")" \
    "$(format_number "$planned_cost")" \
    "$(format_number "$planned_files")" \
    "$modules" \
    "$split_reason"
done

echo
echo "Java 行覆盖: $(format_number "$COMPLETED_LOC") / $(format_number "$TOTAL_JAVA_LOC")"
echo
echo "本轮可执行批次: ${RUNNABLE_BATCHES[*]:-无}"
echo "说明: 已完成批次会自动跳过；待执行和失败待重试批次可以在本轮调度。"
echo "也可以自行输入批次号，例如 batch-002,batch-004 或 2,4,7。"

RUNNABLE_COUNT="${#RUNNABLE_BATCHES[@]}"
MINUTES_PER_BATCH="$(per_batch_minutes "$REVIEW_MODE")"
echo
echo "推荐执行计划"
echo "预估耗时基于 ${REVIEW_MODE:-standard} 模式大型批次，每批约 ${MINUTES_PER_BATCH} 分钟；最终耗时会随机器性能和代码复杂度波动。"
display_plan_row "执行 3 批" 3 "$MINUTES_PER_BATCH" "$RUNNABLE_COUNT"
display_plan_row "执行 5 批（推荐）" 5 "$MINUTES_PER_BATCH" "$RUNNABLE_COUNT"
display_plan_row "执行 10 批" 10 "$MINUTES_PER_BATCH" "$RUNNABLE_COUNT"
display_plan_row "执行全部未完成批次" "$RUNNABLE_COUNT" "$MINUTES_PER_BATCH" "$RUNNABLE_COUNT"
