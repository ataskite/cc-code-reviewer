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
       CC_REVIEW_CONTEXT_SCALE=1 \
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
test -f "$RUN_DIR/batches/batch-001.json"
grep -q '"planned_source_loc"' "$RUN_DIR/batches/batch-001.json"
grep -q '"planned_source_file_count"' "$RUN_DIR/batches/batch-001.json"
grep -q '"batch_file_list"' "$RUN_DIR/batches/batch-001.json"

echo "PASS: core plan-file-batches"
