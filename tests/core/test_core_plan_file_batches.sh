#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/core-plan.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

D="$TMP_DIR/app"; mkdir -p "$D/src"
for i in 1 2 3 4 5; do
  { printf 'export const X%d: number = 0;\n' "$i"; seq 1 9000 | sed 's/.*/export const y& = 0;/'; } > "$D/src/m${i}.ts"
done
D="$(cd "$D" && pwd -P)"

MANIFEST="$(mktemp)"
find "$D/src" -name '*.ts' -print | sort > "$MANIFEST"

OUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260623-010000 \
       bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$D" "standard" "main" "frontend" "$MANIFEST")"

RUN_DIR="$(printf '%s\n' "$OUT" | sed -n 's/^RUN_DIR=//p')"
grep -q "RUN_ID=" <<< "$OUT"
grep -q "BATCH_COUNT=" <<< "$OUT"
grep -q "TOTAL_SOURCE_FILE_COUNT=5" <<< "$OUT"
grep -q "TOTAL_SOURCE_LOC=" <<< "$OUT"
grep -q "BATCH_FILE_LIST_DIR=" <<< "$OUT"
grep -q '"language_id": "frontend"' "$RUN_DIR/plan.json"
grep -q '"strategy": "file-token-batching"' "$RUN_DIR/plan.json"
grep -q '"schema_version": 1' "$RUN_DIR/plan.json"
grep -q '"batch_token_budget": 500000' "$RUN_DIR/plan.json"
grep -q '"context_scale": 5' "$RUN_DIR/plan.json"
grep -q '"context_window_tokens": 1000000' "$RUN_DIR/plan.json"
test -f "$RUN_DIR/batches/batch-001.json"
grep -q '"planned_source_loc"' "$RUN_DIR/batches/batch-001.json"
grep -q '"planned_source_file_count"' "$RUN_DIR/batches/batch-001.json"
grep -q '"batch_file_list"' "$RUN_DIR/batches/batch-001.json"

SCALE_D="$TMP_DIR/large-app"; mkdir -p "$SCALE_D/src"
for i in $(seq -w 1 88); do
  seq 1 10000 | sed 's/.*/export const x = 1;/' > "$SCALE_D/src/file${i}.ts"
done
SCALE_D="$(cd "$SCALE_D" && pwd -P)"
SCALE_MANIFEST="$(mktemp)"
find "$SCALE_D/src" -name '*.ts' -print | sort > "$SCALE_MANIFEST"

SCALE_OUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260623-020000 \
             CC_REVIEW_CONTEXT_SCALE=1 \
             bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$SCALE_D" "standard" "main" "frontend" "$SCALE_MANIFEST")"
SCALE_RUN_DIR="$(printf '%s\n' "$SCALE_OUT" | sed -n 's/^RUN_DIR=//p')"
SCALE_BATCH_COUNT="$(printf '%s\n' "$SCALE_OUT" | sed -n 's/^BATCH_COUNT=//p')"
test "$SCALE_BATCH_COUNT" -eq 6
perl -MJSON::PP -e '
  open my $fh, "<", $ARGV[0] or die $!;
  local $/;
  my $d = decode_json(<$fh>);
  my $b = $d->{budget} || {};
  die "bad batch_token_budget\n" unless ($b->{batch_token_budget} // 0) == 500000;
  die "missing context_scale\n" unless ($b->{context_scale} // 0) == 5;
  die "missing context_window_tokens\n" unless ($b->{context_window_tokens} // 0) == 1000000;
' "$SCALE_RUN_DIR/plan.json"
STATUS_OUT="$(bash "$ROOT_DIR/scripts/core/show-batch-status.sh" "$SCALE_D")"
grep -q "上下文窗口: 1000000 tokens" <<< "$STATUS_OUT"

# 大小不均文件应使用 First-Fit Decreasing 回填已有批次：旧 Next-Fit 会产生 3 批，新算法应为 2 批。
FFD_D="$TMP_DIR/ffd-app"; mkdir -p "$FFD_D/src"
for spec in "large-a:1833" "large-b:1833" "small-a:1167" "small-b:1167"; do
  name="${spec%%:*}"; lines="${spec##*:}"
  seq 1 "$lines" | sed 's/.*/export const value = 1;/' > "$FFD_D/src/$name.ts"
done
FFD_D="$(cd "$FFD_D" && pwd -P)"
FFD_MANIFEST="$(mktemp)"
find "$FFD_D/src" -name '*.ts' -print | sort > "$FFD_MANIFEST"
FFD_OUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260623-030000 \
           CC_REVIEW_CONTEXT_SCALE=1 \
           CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET=10000 \
           bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$FFD_D" "standard" "main" "frontend" "$FFD_MANIFEST")"
FFD_RUN_DIR="$(printf '%s\n' "$FFD_OUT" | sed -n 's/^RUN_DIR=//p')"
test "$(printf '%s\n' "$FFD_OUT" | sed -n 's/^BATCH_COUNT=//p')" -eq 2
test "$(cat "$FFD_RUN_DIR"/batches/*.files | sort | uniq | wc -l | tr -d ' ')" -eq 4
test "$(cat "$FFD_RUN_DIR"/batches/*.files | wc -l | tr -d ' ')" -eq 4
grep -q '"batch_token_budget": 10000' "$FFD_RUN_DIR/plan.json"
grep -q '"context_scale": 5' "$FFD_RUN_DIR/plan.json"

echo "PASS: core plan-file-batches"
