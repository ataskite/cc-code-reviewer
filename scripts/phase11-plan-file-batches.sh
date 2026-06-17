#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"
REVIEW_MODE="${2:?请输入审查模式}"
BRANCH_NAME="${3:-no-branch}"

# 模型上下文窗口缩放系数：1 = 200k（旧行为），5 = 1M 窗口
# 由 phase14-detect-model-context.sh 探测，主 skill 通过环境变量注入
CONTEXT_SCALE="${CC_REVIEW_CONTEXT_SCALE:-1}"
[ "$CONTEXT_SCALE" -lt 1 ] 2>/dev/null && CONTEXT_SCALE=1
[ "$CONTEXT_SCALE" -gt 10 ] && CONTEXT_SCALE=10

# token 预算按 scale 缩放：显式环境变量 > scale 缩放默认值（向后兼容）
BATCH_TOKEN_BUDGET="${CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET:-$((100000 * CONTEXT_SCALE))}"
LINE_TOKEN_ESTIMATE=3
FILE_TOKEN_OVERHEAD=500

json_escape() {
  printf '%s' "$1" | perl -0pe 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\t/\\t/g; s/\r/\\r/g'
}

branch_slug() {
  local slug
  slug="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//' | cut -c1-40)"
  if [ -z "$slug" ]; then
    slug="no-branch"
  fi
  printf '%s' "$slug"
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

risk_priority() {
  local file_name="$1"
  case "$file_name" in
    *Controller.java|*Service.java|*Security*.java|*Filter.java|*Interceptor.java) echo 0 ;;
    *Client.java|*Pool.java|*Scheduler.java|*Handler.java|*Consumer.java|*Producer.java) echo 1 ;;
    *) echo 2 ;;
  esac
}

batch_summary() {
  local draft_file="$1"
  perl -CS -Mutf8 -e '
    binmode STDOUT, ":utf8";
    my @items;
    my $count = 0;
    while (<>) {
      chomp;
      my @fields = split /\t/;
      next unless defined $fields[3];
      $count++;
      push @items, $fields[3] if @items < 2;
    }
    my $summary = join(",", @items);
    if ($count > 2) {
      $summary .= "，等 ${count} 个文件";
    }
    print $summary;
  ' "$draft_file"
}

write_json_string_array_from_draft() {
  local draft_file="$1"
  local max_count="${2:-5}"
  perl -CS -Mutf8 -MJSON::PP -e '
    binmode STDOUT, ":utf8";
    my ($max_count) = @ARGV;
    my @files;
    while (<STDIN>) {
      chomp;
      my @fields = split /\t/;
      next unless defined $fields[3];
      push @files, $fields[3];
      last if @files >= $max_count;
    }
    print encode_json(\@files);
  ' "$max_count" < "$draft_file"
}

sum_field() {
  local file="$1"
  local field="$2"
  awk -F '\t' -v field="$field" '{sum += $field} END {print sum + 0}' "$file"
}

flush_batch() {
  local draft_file="$1"
  [ -s "$draft_file" ] || return 0

  BATCH_COUNT=$((BATCH_COUNT + 1))
  local batch_id batch_file batch_json batch_loc batch_cost batch_files summary
  batch_id="$(printf 'batch-%03d' "$BATCH_COUNT")"
  batch_file="$RUN_DIR/batches/$batch_id.files"
  batch_json="$RUN_DIR/batches/$batch_id.json"
  batch_loc="$(sum_field "$draft_file" 3)"
  batch_cost="$(sum_field "$draft_file" 2)"
  batch_files="$(awk 'END {print NR + 0}' "$draft_file")"
  summary="$(batch_summary "$draft_file")"

  awk -F '\t' '{print $5}' "$draft_file" > "$batch_file"

  cat > "$batch_json.tmp" <<JSON
{
  "schema_version": 1,
  "run_id": "$(json_escape "$RUN_ID")",
  "batch_id": "$batch_id",
  "strategy": "file-token-batching",
  "planned_java_loc": $batch_loc,
  "planned_review_cost": $batch_cost,
  "planned_java_file_count": $batch_files,
  "batch_file_list": "$(json_escape "$batch_file")",
  "sample_files": $(write_json_string_array_from_draft "$draft_file" 5)
}
JSON
  mv "$batch_json.tmp" "$batch_json"
  printf '%s\t%s\t%s\t%s\t%s\n' "$batch_id" "$batch_loc" "$batch_files" "$batch_cost" "$summary" >> "$PLAN_ROWS_TSV"
  : > "$draft_file"
}

if ! [[ "$BATCH_TOKEN_BUDGET" =~ ^[0-9]+$ ]] || [ "$BATCH_TOKEN_BUDGET" -le 0 ]; then
  echo "INVALID_BATCH_TOKEN_BUDGET=$BATCH_TOKEN_BUDGET" >&2
  exit 1
fi

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
RUN_TIMESTAMP="${CC_CODE_REVIEWER_RUN_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
RUN_ID="$RUN_TIMESTAMP-$(branch_slug "$BRANCH_NAME")-$REVIEW_MODE"
RUNS_ROOT="${CC_CODE_REVIEWER_RUNS_ROOT:-$PROJECT_DIR/.cc-code-reviewer/runs}"
RUN_DIR="$RUNS_ROOT/$RUN_ID"
FILES_TSV="$RUN_DIR/java-files.tsv"
SORTED_FILES_TSV="$RUN_DIR/java-files.sorted.tsv"
DRAFT_FILE="$RUN_DIR/current-batch.tsv"
PLAN_ROWS_TSV="$RUN_DIR/batch-plan.tsv"

mkdir -p "$RUN_DIR/batches" "$RUN_DIR/results"
: > "$FILES_TSV"
: > "$PLAN_ROWS_TSV"
: > "$DRAFT_FILE"

while IFS= read -r -d '' file; do
  rel_path="${file#$PROJECT_DIR/}"
  file_name="${file##*/}"
  loc="$(wc -l < "$file" | tr -d ' ')"
  cost=$((loc * LINE_TOKEN_ESTIMATE + FILE_TOKEN_OVERHEAD))
  priority="$(risk_priority "$file_name")"
  printf '%s\t%s\t%s\t%s\t%s\n' "$priority" "$cost" "$loc" "$rel_path" "$file" >> "$FILES_TSV"
done < <(find "$PROJECT_DIR" -path '*/src/main/java/*' -name '*.java' -not -path '*/target/*' -not -path '*/build/*' -not -path '*/.git/*' -print0 2>/dev/null)

if [ ! -s "$FILES_TSV" ]; then
  echo "NO_JAVA_FILES=$PROJECT_DIR" >&2
  exit 1
fi

sort -t "$(printf '\t')" -k1,1n -k2,2rn -k4,4 "$FILES_TSV" > "$SORTED_FILES_TSV"

TOTAL_JAVA_LOC="$(sum_field "$FILES_TSV" 3)"
TOTAL_JAVA_FILE_COUNT="$(awk 'END {print NR + 0}' "$FILES_TSV")"
BATCH_COUNT=0
CURRENT_BATCH_COST=0

while IFS="$(printf '\t')" read -r priority cost loc rel_path abs_path; do
  [ -n "$abs_path" ] || continue
  if [ "$CURRENT_BATCH_COST" -gt 0 ] && [ $((CURRENT_BATCH_COST + cost)) -gt "$BATCH_TOKEN_BUDGET" ]; then
    flush_batch "$DRAFT_FILE"
    CURRENT_BATCH_COST=0
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$priority" "$cost" "$loc" "$rel_path" "$abs_path" >> "$DRAFT_FILE"
  CURRENT_BATCH_COST=$((CURRENT_BATCH_COST + cost))
done < "$SORTED_FILES_TSV"

flush_batch "$DRAFT_FILE"

CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$RUN_DIR/plan.json.tmp" <<JSON
{
  "schema_version": 1,
  "run_id": "$(json_escape "$RUN_ID")",
  "project_name": "$(json_escape "$PROJECT_NAME")",
  "project_dir": "$(json_escape "$PROJECT_DIR")",
  "review_mode": "$(json_escape "$REVIEW_MODE")",
  "branch": "$(json_escape "$BRANCH_NAME")",
  "strategy": "file-token-batching",
  "total_java_loc": $TOTAL_JAVA_LOC,
  "total_java_file_count": $TOTAL_JAVA_FILE_COUNT,
  "batch_count": $BATCH_COUNT,
  "budget": {
    "batch_token_budget": $BATCH_TOKEN_BUDGET,
    "line_token_estimate": $LINE_TOKEN_ESTIMATE,
    "file_token_overhead": $FILE_TOKEN_OVERHEAD
  },
  "created_at": "$CREATED_AT"
}
JSON
mv "$RUN_DIR/plan.json.tmp" "$RUN_DIR/plan.json"

printf '{"event":"file_batches_planned","run_id":"%s","batch_count":%s,"created_at":"%s"}\n' \
  "$(json_escape "$RUN_ID")" "$BATCH_COUNT" "$CREATED_AT" > "$RUN_DIR/progress.jsonl"

rm -f "$DRAFT_FILE" "$FILES_TSV" "$SORTED_FILES_TSV"

echo "RUN_ID=$RUN_ID"
echo "RUN_DIR=$RUN_DIR"
echo "BATCH_COUNT=$BATCH_COUNT"
echo "TOTAL_JAVA_LOC=$TOTAL_JAVA_LOC"
echo "TOTAL_JAVA_FILE_COUNT=$TOTAL_JAVA_FILE_COUNT"
echo "BATCH_FILE_LIST_DIR=$RUN_DIR/batches"
echo
echo "简要分批计划"
echo "批次 行数 文件 重点范围"
while IFS="$(printf '\t')" read -r batch_id batch_loc batch_files _batch_cost summary; do
  [ -n "$batch_id" ] || continue
  printf '%s %s %s %s\n' "$batch_id" "$(format_number "$batch_loc")" "$(format_number "$batch_files")" "$summary"
done < "$PLAN_ROWS_TSV"
