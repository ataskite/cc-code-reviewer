#!/bin/bash
set -euo pipefail

RUN_DIR="${1:?请输入运行目录 RUN_DIR}"

if [ ! -d "$RUN_DIR" ]; then
  echo "RUN_DIR_NOT_FOUND=$RUN_DIR" >&2
  exit 1
fi

PLAN_PATH="$RUN_DIR/plan.json"
if [ ! -f "$PLAN_PATH" ]; then
  echo "PLAN_JSON_NOT_FOUND=$PLAN_PATH" >&2
  exit 1
fi

json_escape() {
  printf '%s' "$1" | perl -0pe 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\t/\\t/g; s/\r/\\r/g'
}

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

resolve_result_path() {
  local result_path="$1"
  if [ -z "$result_path" ]; then
    return 0
  fi
  case "$result_path" in
    /*) printf '%s\n' "$result_path" ;;
    *) printf '%s\n' "$RUN_DIR/$result_path" ;;
  esac
}

format_number() {
  local value="${1:-0}"
  [ -n "$value" ] || value=0
  perl -e '
    my $n = shift;
    $n = 0 if !defined($n) || $n eq "";
    1 while $n =~ s/^(-?\d+)(\d{3})/$1,$2/;
    print $n;
  ' "$value"
}

percent() {
  local part="${1:-0}"
  local total="${2:-0}"
  if [ "$total" -gt 0 ]; then
    echo $((part * 100 / total))
  else
    echo 0
  fi
}

status_label() {
  case "${1:-pending}" in
    completed) echo "已完成" ;;
    failed) echo "失败" ;;
    running) echo "执行中" ;;
    *) echo "待执行" ;;
  esac
}

markdown_cell() {
  printf '%s' "$1" | tr '\n\r' '  ' | sed 's/|/\\|/g'
}

normalize_batch_id() {
  local raw="$1"
  raw="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$raw" ] || return 0
  case "$raw" in
    batch-[0-9][0-9][0-9]) printf '%s\n' "$raw" ;;
    batch-[0-9]) printf 'batch-%03d\n' "${raw#batch-}" ;;
    batch-[0-9][0-9]) printf 'batch-%03d\n' "${raw#batch-}" ;;
    [0-9]*) printf 'batch-%03d\n' "$raw" ;;
    *) printf '%s\n' "$raw" ;;
  esac
}

json_string_array() {
  local first=1
  local item
  printf '['
  for item in "$@"; do
    [ -n "$item" ] || continue
    if [ "$first" -eq 0 ]; then
      printf ', '
    fi
    printf '"%s"' "$(json_escape "$item")"
    first=0
  done
  printf ']'
}

PROJECT_NAME="$(json_get "$PLAN_PATH" project_name)"
RUN_ID="$(json_get "$PLAN_PATH" run_id)"
REVIEW_MODE="$(json_get "$PLAN_PATH" review_mode)"
REVIEW_SCOPE="$(json_get "$PLAN_PATH" review_scope)"
SEMANTIC_LEVEL="$(json_get "$PLAN_PATH" semantic_level)"
TOTAL_JAVA_LOC="$(json_get "$PLAN_PATH" total_java_loc)"
TOTAL_JAVA_FILE_COUNT="$(json_get "$PLAN_PATH" total_java_file_count)"
BATCH_COUNT="$(json_get "$PLAN_PATH" batch_count)"

[ -n "$PROJECT_NAME" ] || PROJECT_NAME="$(basename "$(dirname "$(dirname "$RUN_DIR")")")"
[ -n "$RUN_ID" ] || RUN_ID="$(basename "$RUN_DIR")"
[ -n "$REVIEW_MODE" ] || REVIEW_MODE="unknown"
[ -n "$REVIEW_SCOPE" ] || REVIEW_SCOPE="全量代码"
[ -n "$SEMANTIC_LEVEL" ] || SEMANTIC_LEVEL="maven-static"
[ -n "$TOTAL_JAVA_LOC" ] || TOTAL_JAVA_LOC=0
[ -n "$TOTAL_JAVA_FILE_COUNT" ] || TOTAL_JAVA_FILE_COUNT=0
[ -n "$BATCH_COUNT" ] || BATCH_COUNT=0

ALL_BATCH_IDS=()
for batch_path in "$RUN_DIR"/batches/batch-*.json; do
  [ -f "$batch_path" ] || continue
  batch_id="$(json_get "$batch_path" batch_id)"
  [ -n "$batch_id" ] || batch_id="$(basename "$batch_path" .json)"
  ALL_BATCH_IDS+=("$batch_id")
done

TARGET_BATCH_IDS=()
if [ -n "${RUN_BATCH_IDS:-}" ]; then
  normalized_input="$(printf '%s' "$RUN_BATCH_IDS" | perl -CS -Mutf8 -pe 's/[，、,\s]+/ /g')"
  for raw_batch_id in $normalized_input; do
    batch_id="$(normalize_batch_id "$raw_batch_id")"
    [ -n "$batch_id" ] || continue
    TARGET_BATCH_IDS+=("$batch_id")
  done
else
  TARGET_BATCH_IDS=("${ALL_BATCH_IDS[@]}")
fi
TARGET_BATCH_COUNT="${#TARGET_BATCH_IDS[@]}"

batch_id_exists() {
  local candidate="$1"
  local existing
  for existing in "${ALL_BATCH_IDS[@]}"; do
    if [ "$existing" = "$candidate" ]; then
      return 0
    fi
  done
  return 1
}

for target_batch_id in "${TARGET_BATCH_IDS[@]}"; do
  if ! batch_id_exists "$target_batch_id"; then
    echo "TARGET_BATCH_NOT_FOUND=$target_batch_id" >&2
    exit 1
  fi
done

is_target_batch() {
  local candidate="$1"
  local target
  for target in "${TARGET_BATCH_IDS[@]}"; do
    if [ "$target" = "$candidate" ]; then
      return 0
    fi
  done
  return 1
}

target_has_nonterminal_batches() {
  local target status_path status
  for target in "${TARGET_BATCH_IDS[@]}"; do
    status_path="$RUN_DIR/results/$target.status.json"
    status="pending"
    if [ -f "$status_path" ]; then
      status="$(json_get "$status_path" status)"
      [ -n "$status" ] || status="pending"
    fi
    case "$status" in
      completed|failed) ;;
      *) return 0 ;;
    esac
  done
  return 1
}

MERGE_WAIT_TIMEOUT_SECONDS="${MERGE_WAIT_TIMEOUT_SECONDS:-300}"
MERGE_POLL_INTERVAL_SECONDS="${MERGE_POLL_INTERVAL_SECONDS:-5}"
WAIT_TIMED_OUT=false
if target_has_nonterminal_batches; then
  wait_start="$(date +%s)"
  while target_has_nonterminal_batches; do
    wait_now="$(date +%s)"
    if [ $((wait_now - wait_start)) -ge "$MERGE_WAIT_TIMEOUT_SECONDS" ]; then
      WAIT_TIMED_OUT=true
      break
    fi
    sleep "$MERGE_POLL_INTERVAL_SECONDS"
  done
fi

mkdir -p "$RUN_DIR/final"
COMPLETED_RESULTS="$RUN_DIR/final/.completed-results.md"
CROSS_BATCH_LEADS="$RUN_DIR/final/.cross-batch-leads.md"
BATCH_STATUS_TABLE="$RUN_DIR/final/.batch-status-table.md"
: > "$COMPLETED_RESULTS"
: > "$CROSS_BATCH_LEADS"
: > "$BATCH_STATUS_TABLE"

COMPLETED_BATCHES=0
FAILED_BATCHES=0
PENDING_BATCHES=0
RUNNING_BATCHES=0
COVERED_LOC=0
COVERED_FILES=0
TOTAL_FINDINGS=0
INCLUDED_BATCHES=0
LEFTOVER_BATCHES=0
MERGE_BLOCKED=false
INCLUDED_BATCH_IDS=()
LEFTOVER_BATCH_IDS=()

{
  echo "| 批次 | 状态 | 本轮主任务 | 合并处理 | 文件数 | 行数 | 模块 | 错误 |"
  echo "|---|---|---|---|---:|---:|---|---|"
} > "$BATCH_STATUS_TABLE"

for batch_path in "$RUN_DIR"/batches/batch-*.json; do
  [ -f "$batch_path" ] || continue
  batch_id="$(json_get "$batch_path" batch_id)"
  [ -n "$batch_id" ] || batch_id="$(basename "$batch_path" .json)"
  planned_loc="$(json_get "$batch_path" planned_java_loc)"
  planned_files="$(json_get "$batch_path" planned_java_file_count)"
  [ -n "$planned_loc" ] || planned_loc=0
  [ -n "$planned_files" ] || planned_files=0

  status_path="$RUN_DIR/results/$batch_id.status.json"
  status="pending"
  result_path=""
  finding_count=0
  error=""
  if [ -f "$status_path" ]; then
    status="$(json_get "$status_path" status)"
    status_loc="$(json_get "$status_path" planned_java_loc)"
    status_files="$(json_get "$status_path" planned_java_file_count)"
    result_path="$(json_get "$status_path" result_path)"
    finding_count="$(json_get "$status_path" finding_count)"
    error="$(json_get "$status_path" error)"
    [ -n "$status_loc" ] && planned_loc="$status_loc"
    [ -n "$status_files" ] && planned_files="$status_files"
    [ -n "$finding_count" ] || finding_count=0
  fi
  [ -n "$status" ] || status="pending"

  resolved_result_path="$(resolve_result_path "$result_path")"
  target_label="否"
  merge_action="未纳入本轮，遗留"
  result_available=false
  if [ -n "$resolved_result_path" ] && [ -f "$resolved_result_path" ]; then
    result_available=true
  fi

  case "$status" in
    completed)
      COMPLETED_BATCHES=$((COMPLETED_BATCHES + 1))
      if is_target_batch "$batch_id" && [ "$result_available" = true ]; then
        target_label="是"
        merge_action="已纳入本次合并"
        INCLUDED_BATCHES=$((INCLUDED_BATCHES + 1))
        INCLUDED_BATCH_IDS+=("$batch_id")
        COVERED_LOC=$((COVERED_LOC + planned_loc))
        COVERED_FILES=$((COVERED_FILES + planned_files))
        TOTAL_FINDINGS=$((TOTAL_FINDINGS + finding_count))
        {
          echo ""
          echo "### $batch_id - $(batch_modules "$batch_path")"
          echo ""
          cat "$resolved_result_path"
          echo ""
        } >> "$COMPLETED_RESULTS"
        awk '
          /^##[[:space:]]*跨批依赖待复核/ {capture=1; next}
          /^##[[:space:]]/ {capture=0}
          capture && NF > 0 {print}
        ' "$resolved_result_path" >> "$CROSS_BATCH_LEADS"
      elif is_target_batch "$batch_id"; then
        target_label="是"
        merge_action="结果缺失遗留"
        LEFTOVER_BATCHES=$((LEFTOVER_BATCHES + 1))
        LEFTOVER_BATCH_IDS+=("$batch_id")
        MERGE_BLOCKED=true
      else
        LEFTOVER_BATCHES=$((LEFTOVER_BATCHES + 1))
        LEFTOVER_BATCH_IDS+=("$batch_id")
      fi
      ;;
    failed)
      FAILED_BATCHES=$((FAILED_BATCHES + 1))
      if is_target_batch "$batch_id"; then
        target_label="是"
        merge_action="失败遗留"
        MERGE_BLOCKED=true
      fi
      LEFTOVER_BATCHES=$((LEFTOVER_BATCHES + 1))
      LEFTOVER_BATCH_IDS+=("$batch_id")
      ;;
    running)
      RUNNING_BATCHES=$((RUNNING_BATCHES + 1))
      if is_target_batch "$batch_id"; then
        target_label="是"
        merge_action="未完成遗留"
        MERGE_BLOCKED=true
      fi
      LEFTOVER_BATCHES=$((LEFTOVER_BATCHES + 1))
      LEFTOVER_BATCH_IDS+=("$batch_id")
      ;;
    *)
      PENDING_BATCHES=$((PENDING_BATCHES + 1))
      if is_target_batch "$batch_id"; then
        target_label="是"
        merge_action="未完成遗留"
        MERGE_BLOCKED=true
      fi
      LEFTOVER_BATCHES=$((LEFTOVER_BATCHES + 1))
      LEFTOVER_BATCH_IDS+=("$batch_id")
      ;;
  esac

  if [ "$WAIT_TIMED_OUT" = true ] && is_target_batch "$batch_id"; then
    case "$status" in
      completed|failed) ;;
      *)
        MERGE_BLOCKED=true
        error="${error:-等待本轮批次完成超时}"
        ;;
    esac
  fi

  printf '| %s | %s | %s | %s | %s | %s | %s | %s |\n' \
    "$(markdown_cell "$batch_id")" \
    "$(markdown_cell "$(status_label "$status")")" \
    "$target_label" \
    "$(markdown_cell "$merge_action")" \
    "$(format_number "$planned_files")" \
    "$(format_number "$planned_loc")" \
    "$(markdown_cell "$(batch_modules "$batch_path")")" \
    "$(markdown_cell "$error")" >> "$BATCH_STATUS_TABLE"
done

LOC_COVERAGE="$(percent "$COVERED_LOC" "$TOTAL_JAVA_LOC")"
FILE_COVERAGE="$(percent "$COVERED_FILES" "$TOTAL_JAVA_FILE_COUNT")"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SAFE_PROJECT_NAME="$(printf '%s' "$PROJECT_NAME" | sed 's/[^A-Za-z0-9._-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//')"
[ -n "$SAFE_PROJECT_NAME" ] || SAFE_PROJECT_NAME="project"
FINAL_REPORT="$RUN_DIR/final/code-review-report-$SAFE_PROJECT_NAME-$TIMESTAMP.md"

if [ "$MERGE_BLOCKED" = true ]; then
  REPORT_TITLE="[合并阻塞] 代码审查报告 - $PROJECT_NAME"
elif [ "$COMPLETED_BATCHES" -lt "$BATCH_COUNT" ]; then
  REPORT_TITLE="[阶段性] 代码审查报告 - $PROJECT_NAME"
else
  REPORT_TITLE="代码审查报告 - $PROJECT_NAME"
fi

cat > "$RUN_DIR/summary.json.tmp" <<JSON
{
  "schema_version": 1,
  "run_id": "$(json_escape "$RUN_ID")",
  "completed_batches": $COMPLETED_BATCHES,
  "failed_batches": $FAILED_BATCHES,
  "pending_batches": $PENDING_BATCHES,
  "running_batches": $RUNNING_BATCHES,
  "batch_count": $BATCH_COUNT,
  "target_batch_count": $TARGET_BATCH_COUNT,
  "included_batches": $INCLUDED_BATCHES,
  "leftover_batches": $LEFTOVER_BATCHES,
  "merge_blocked": $MERGE_BLOCKED,
  "wait_timed_out": $WAIT_TIMED_OUT,
  "target_batch_ids": $(json_string_array ${TARGET_BATCH_IDS[@]+"${TARGET_BATCH_IDS[@]}"}),
  "included_batch_ids": $(json_string_array ${INCLUDED_BATCH_IDS[@]+"${INCLUDED_BATCH_IDS[@]}"}),
  "leftover_batch_ids": $(json_string_array ${LEFTOVER_BATCH_IDS[@]+"${LEFTOVER_BATCH_IDS[@]}"}),
  "covered_java_loc": $COVERED_LOC,
  "total_java_loc": $TOTAL_JAVA_LOC,
  "java_loc_coverage_percent": $LOC_COVERAGE,
  "covered_java_file_count": $COVERED_FILES,
  "total_java_file_count": $TOTAL_JAVA_FILE_COUNT,
  "java_file_coverage_percent": $FILE_COVERAGE,
  "finding_count": $TOTAL_FINDINGS,
  "final_report_path": "$(json_escape "$FINAL_REPORT")"
}
JSON
mv "$RUN_DIR/summary.json.tmp" "$RUN_DIR/summary.json"

cat > "$FINAL_REPORT.tmp" <<MD
# $REPORT_TITLE

## 大仓库审查执行摘要

- Run ID：$RUN_ID
- 审查模式：$REVIEW_MODE
- 审查范围：$REVIEW_SCOPE
- 语义增强：$SEMANTIC_LEVEL
- 本轮主任务批次：$TARGET_BATCH_COUNT / $BATCH_COUNT
- 批次完成：$COMPLETED_BATCHES / $BATCH_COUNT
- 失败待重试批次：$FAILED_BATCHES
- 待执行批次：$PENDING_BATCHES
- 执行中批次：$RUNNING_BATCHES
- 已纳入本次合并批次：$INCLUDED_BATCHES
- 遗留批次：$LEFTOVER_BATCHES
- Java 文件覆盖：$(format_number "$COVERED_FILES") / $(format_number "$TOTAL_JAVA_FILE_COUNT")（$FILE_COVERAGE%）
- 已完成批次 Java 行规模：$(format_number "$COVERED_LOC") / $(format_number "$TOTAL_JAVA_LOC")（规划规模参考，不作为覆盖率口径）
- 已合并问题数：$TOTAL_FINDINGS

## 批次状态总览

MD

cat "$BATCH_STATUS_TABLE" >> "$FINAL_REPORT.tmp"

cat >> "$FINAL_REPORT.tmp" <<'MD'

## 已完成批次发现

MD

if [ -s "$COMPLETED_RESULTS" ]; then
  cat "$COMPLETED_RESULTS" >> "$FINAL_REPORT.tmp"
else
  echo "暂无已完成批次发现。" >> "$FINAL_REPORT.tmp"
fi

cat >> "$FINAL_REPORT.tmp" <<'MD'

## 跨批依赖线索

MD

if [ -s "$CROSS_BATCH_LEADS" ]; then
  sort -u "$CROSS_BATCH_LEADS" >> "$FINAL_REPORT.tmp"
else
  echo "暂无跨批依赖线索。 " >> "$FINAL_REPORT.tmp"
fi

cat >> "$FINAL_REPORT.tmp" <<'MD'

## 覆盖说明

本报告只合并本轮主任务中状态为“已完成”且结果文件存在的批次。失败、待执行、执行中、结果缺失或未纳入本轮的批次不会进入正式问题结论，详见“批次状态总览”。
Java 文件覆盖率是唯一覆盖指标；LOC 与 review cost 仅作为分批规划和进度参考。
MD

mv "$FINAL_REPORT.tmp" "$FINAL_REPORT"
rm -f "$COMPLETED_RESULTS" "$CROSS_BATCH_LEADS" "$BATCH_STATUS_TABLE"

echo "SUMMARY_PATH=$RUN_DIR/summary.json"
echo "FINAL_REPORT_PATH=$FINAL_REPORT"
if [ "$MERGE_BLOCKED" = true ]; then
  echo "MERGE_BLOCKED=true"
  exit 2
fi
