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
    if (ref($data->{modules}) eq "ARRAY") {
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
echo "批次 状态 行数 文件 模块"

COMPLETED_LOC=0
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
  if [ -f "$status_path" ]; then
    status="$(json_get "$status_path" status)"
    status_loc="$(json_get "$status_path" planned_java_loc)"
    status_files="$(json_get "$status_path" planned_java_file_count)"
    if [ -n "$status_loc" ]; then
      planned_loc="$status_loc"
    fi
    if [ -n "$status_files" ]; then
      planned_files="$status_files"
    fi
  fi
  planned_loc="${planned_loc:-0}"
  planned_files="${planned_files:-0}"
  modules="$(batch_modules "$batch_path")"

  if [ "$status" = "completed" ]; then
    COMPLETED_LOC=$((COMPLETED_LOC + planned_loc))
  fi

  printf '%s %s %s %s %s\n' \
    "$batch_id" \
    "$(status_label "$status")" \
    "$(format_number "$planned_loc")" \
    "$(format_number "$planned_files")" \
    "$modules"
done

echo
echo "Java 行覆盖: $(format_number "$COMPLETED_LOC") / $(format_number "$TOTAL_JAVA_LOC")"
