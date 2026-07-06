#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"
REVIEW_MODE="${2:?请输入审查模式}"
BRANCH_NAME="${3:-no-branch}"
LANGUAGE_ID="${4:?请输入语言 ID}"
SOURCE_MANIFEST="${5:?请输入 source manifest 路径}"

# 模型上下文窗口缩放系数：1 = 200k，5 = 1M（由 core/detect-model-context.sh 探测）
CONTEXT_SCALE="${CC_REVIEW_CONTEXT_SCALE:-1}"
[ "$CONTEXT_SCALE" -lt 1 ] 2>/dev/null && CONTEXT_SCALE=1
[ "$CONTEXT_SCALE" -gt 10 ] && CONTEXT_SCALE=10

BATCH_TOKEN_BUDGET="${CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET:-$((100000 * CONTEXT_SCALE))}"
LINE_TOKEN_ESTIMATE=3
FILE_TOKEN_OVERHEAD=500

json_escape() { printf '%s' "$1" | perl -0pe 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\t/\\t/g; s/\r/\\r/g'; }
branch_slug() {
  local s; s="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//' | cut -c1-40)"
  [ -n "$s" ] || s="no-branch"; printf '%s' "$s"
}
sum_field() { awk -F '\t' -v f="$2" '{s+=$f} END{print s+0}' "$1"; }

# 语言中性的风险优先级：路由/页面/组件入口优先
risk_priority() {
  case "$1" in
    *route*|*Router*|*Page*|*App.tsx|*App.jsx|*index.tsx|*main.tsx) echo 0 ;;
    *Service*|*api*|*hook*|*Hook*|*store*|*Store*) echo 1 ;;
    *) echo 2 ;;
  esac
}

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
RUN_ID="${CC_CODE_REVIEWER_RUN_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}-$(branch_slug "$BRANCH_NAME")-$REVIEW_MODE"
RUNS_ROOT="${CC_CODE_REVIEWER_RUNS_ROOT:-$PROJECT_DIR/.cc-code-reviewer/runs}"
RUN_DIR="$RUNS_ROOT/$RUN_ID"
FILES_TSV="$RUN_DIR/source-files.tsv"; SORTED="$RUN_DIR/source-files.sorted.tsv"
DRAFT="$RUN_DIR/current-batch.tsv"; PLAN_ROWS="$RUN_DIR/batch-plan.tsv"
mkdir -p "$RUN_DIR/batches" "$RUN_DIR/results"
: > "$FILES_TSV"; : > "$PLAN_ROWS"; : > "$DRAFT"

while IFS= read -r file; do
  [ -n "$file" ] || continue
  loc="$(wc -l < "$file" | tr -d ' ')"
  cost=$((loc * LINE_TOKEN_ESTIMATE + FILE_TOKEN_OVERHEAD))
  printf '%s\t%s\t%s\t%s\n' "$(risk_priority "${file##*/}")" "$cost" "$loc" "$file" >> "$FILES_TSV"
done < "$SOURCE_MANIFEST"

if [ ! -s "$FILES_TSV" ]; then
  echo "NO_SOURCE_FILES=$PROJECT_DIR" >&2
  exit 1
fi

sort -t "$(printf '\t')" -k1,1n -k2,2rn "$FILES_TSV" > "$SORTED"
TOTAL_LOC="$(sum_field "$FILES_TSV" 3)"
TOTAL_FILES="$(awk 'END{print NR+0}' "$FILES_TSV")"

BATCH_COUNT=0; CUR_COST=0
flush_batch() {
  [ -s "$DRAFT" ] || return 0
  BATCH_COUNT=$((BATCH_COUNT+1))
  local id; id="$(printf 'batch-%03d' "$BATCH_COUNT")"
  local bf="$RUN_DIR/batches/$id.files"; local bj="$RUN_DIR/batches/$id.json"
  local loc files cost
  loc="$(sum_field "$DRAFT" 3)"; files="$(awk 'END{print NR+0}' "$DRAFT")"; cost="$(sum_field "$DRAFT" 2)"
  awk -F '\t' '{print $4}' "$DRAFT" > "$bf"
  cat > "$bj.tmp" <<JSON
{
  "schema_version": 1,
  "run_id": "$(json_escape "$RUN_ID")",
  "batch_id": "$id",
  "strategy": "file-token-batching",
  "language_id": "$(json_escape "$LANGUAGE_ID")",
  "planned_source_loc": $loc,
  "planned_source_file_count": $files,
  "planned_review_cost": $cost,
  "batch_file_list": "$(json_escape "$bf")"
}
JSON
  mv "$bj.tmp" "$bj"
  printf '%s\t%s\t%s\t%s\n' "$id" "$loc" "$files" "$cost" >> "$PLAN_ROWS"
  : > "$DRAFT"
}

while IFS="$(printf '\t')" read -r pri cost loc file; do
  [ -n "$file" ] || continue
  if [ "$CUR_COST" -gt 0 ] && [ $((CUR_COST + cost)) -gt "$BATCH_TOKEN_BUDGET" ]; then
    flush_batch "$DRAFT"; CUR_COST=0
  fi
  printf '%s\t%s\t%s\t%s\n' "$pri" "$cost" "$loc" "$file" >> "$DRAFT"
  CUR_COST=$((CUR_COST + cost))
done < "$SORTED"
flush_batch "$DRAFT"

CREATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$RUN_DIR/plan.json.tmp" <<JSON
{
  "schema_version": 1,
  "run_id": "$(json_escape "$RUN_ID")",
  "project_name": "$(json_escape "$PROJECT_NAME")",
  "project_dir": "$(json_escape "$PROJECT_DIR")",
  "review_mode": "$(json_escape "$REVIEW_MODE")",
  "branch": "$(json_escape "$BRANCH_NAME")",
  "language_id": "$(json_escape "$LANGUAGE_ID")",
  "strategy": "file-token-batching",
  "total_source_loc": $TOTAL_LOC,
  "total_source_file_count": $TOTAL_FILES,
  "batch_count": $BATCH_COUNT,
  "budget": { "batch_token_budget": $BATCH_TOKEN_BUDGET, "target_batch_cost": $BATCH_TOKEN_BUDGET, "line_token_estimate": $LINE_TOKEN_ESTIMATE, "file_token_overhead": $FILE_TOKEN_OVERHEAD, "context_scale": $CONTEXT_SCALE, "context_window_tokens": $((200000 * CONTEXT_SCALE)) },
  "created_at": "$CREATED"
}
JSON
mv "$RUN_DIR/plan.json.tmp" "$RUN_DIR/plan.json"

rm -f "$DRAFT" "$FILES_TSV" "$SORTED"

echo "RUN_ID=$RUN_ID"
echo "RUN_DIR=$RUN_DIR"
echo "BATCH_COUNT=$BATCH_COUNT"
echo "TOTAL_SOURCE_LOC=$TOTAL_LOC"
echo "TOTAL_SOURCE_FILE_COUNT=$TOTAL_FILES"
echo "BATCH_FILE_LIST_DIR=$RUN_DIR/batches"
exit 0
