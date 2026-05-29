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

mkdir -p "$RUN_DIR/final"
COMPLETED_RESULTS="$RUN_DIR/final/.completed-results.md"
CROSS_BATCH_LEADS="$RUN_DIR/final/.cross-batch-leads.md"
: > "$COMPLETED_RESULTS"
: > "$CROSS_BATCH_LEADS"

COMPLETED_BATCHES=0
FAILED_BATCHES=0
PENDING_BATCHES=0
RUNNING_BATCHES=0
COVERED_LOC=0
COVERED_FILES=0
TOTAL_FINDINGS=0

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
  if [ -f "$status_path" ]; then
    status="$(json_get "$status_path" status)"
    status_loc="$(json_get "$status_path" planned_java_loc)"
    status_files="$(json_get "$status_path" planned_java_file_count)"
    result_path="$(json_get "$status_path" result_path)"
    finding_count="$(json_get "$status_path" finding_count)"
    [ -n "$status_loc" ] && planned_loc="$status_loc"
    [ -n "$status_files" ] && planned_files="$status_files"
    [ -n "$finding_count" ] || finding_count=0
  fi

  resolved_result_path="$(resolve_result_path "$result_path")"
  case "$status" in
    completed)
      if [ -n "$resolved_result_path" ] && [ -f "$resolved_result_path" ]; then
        COMPLETED_BATCHES=$((COMPLETED_BATCHES + 1))
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
      else
        FAILED_BATCHES=$((FAILED_BATCHES + 1))
      fi
      ;;
    failed)
      FAILED_BATCHES=$((FAILED_BATCHES + 1))
      ;;
    running)
      RUNNING_BATCHES=$((RUNNING_BATCHES + 1))
      ;;
    *)
      PENDING_BATCHES=$((PENDING_BATCHES + 1))
      ;;
  esac
done

LOC_COVERAGE="$(percent "$COVERED_LOC" "$TOTAL_JAVA_LOC")"
FILE_COVERAGE="$(percent "$COVERED_FILES" "$TOTAL_JAVA_FILE_COUNT")"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SAFE_PROJECT_NAME="$(printf '%s' "$PROJECT_NAME" | sed 's/[^A-Za-z0-9._-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//')"
[ -n "$SAFE_PROJECT_NAME" ] || SAFE_PROJECT_NAME="project"
FINAL_REPORT="$RUN_DIR/final/code-review-report-$SAFE_PROJECT_NAME-$TIMESTAMP.md"

if [ "$COMPLETED_BATCHES" -lt "$BATCH_COUNT" ]; then
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
- 批次完成：$COMPLETED_BATCHES / $BATCH_COUNT
- 失败待重试批次：$FAILED_BATCHES
- 待执行批次：$PENDING_BATCHES
- 执行中批次：$RUNNING_BATCHES
- Java 行覆盖：$(format_number "$COVERED_LOC") / $(format_number "$TOTAL_JAVA_LOC")（$LOC_COVERAGE%）
- Java 文件覆盖：$(format_number "$COVERED_FILES") / $(format_number "$TOTAL_JAVA_FILE_COUNT")（$FILE_COVERAGE%）
- 已合并问题数：$TOTAL_FINDINGS

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

本报告只合并状态为“已完成”的批次。失败、待执行或执行中的批次不会进入正式问题结论。
MD

mv "$FINAL_REPORT.tmp" "$FINAL_REPORT"
rm -f "$COMPLETED_RESULTS" "$CROSS_BATCH_LEADS"

echo "SUMMARY_PATH=$RUN_DIR/summary.json"
echo "FINAL_REPORT_PATH=$FINAL_REPORT"
