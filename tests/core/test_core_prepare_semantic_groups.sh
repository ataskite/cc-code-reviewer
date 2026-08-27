#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/core/prepare-semantic-groups.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/core-semantic-groups.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_DIR="$TMP_DIR/project"
mkdir -p "$PROJECT_DIR"
INPUT="$TMP_DIR/review-input.json"
OUTPUT="$TMP_DIR/semantic-groups.tsv"

cat > "$INPUT" <<'JSON'
{
  "schema_version": 1,
  "project_dir": "PROJECT_PLACEHOLDER",
  "selection_mode": "incremental",
  "items": [
    {"path":"src/order/OrderService.ts","change":"modified","old_path":"","selected":true,"insertions":20,"deletions":2},
    {"path":"src/order/OrderServiceImpl.ts","change":"modified","old_path":"","selected":true,"insertions":8,"deletions":1},
    {"path":"src/order/OrderService.test.ts","change":"modified","old_path":"","selected":true,"insertions":10,"deletions":0},
    {"path":"src/order/OrderService.spec.ts","change":"modified","old_path":"","selected":true,"insertions":4,"deletions":0},
    {"path":"src/order/OrderService.ts","change":"modified","old_path":"","selected":false,"insertions":0,"deletions":0}
  ]
}
JSON
PG_PROJECT="$PROJECT_DIR" perl -0pi -e 's/PROJECT_PLACEHOLDER/$ENV{PG_PROJECT}/g' "$INPUT"

"$SCRIPT" "$PROJECT_DIR" "$INPUT" "$OUTPUT"
test -s "$OUTPUT"
test "$(awk -F '\t' 'NF == 2 {print $1}' "$OUTPUT" | sort -u | wc -l | tr -d ' ')" -eq 1
test "$(wc -l < "$OUTPUT" | tr -d ' ')" -eq 4
cut -f2 "$OUTPUT" | sort | diff -u - <(printf '%s\n' src/order/OrderService.spec.ts src/order/OrderService.test.ts src/order/OrderService.ts src/order/OrderServiceImpl.ts | sort)

SMALL_INPUT="$TMP_DIR/small.json"
SMALL_OUTPUT="$TMP_DIR/small.tsv"
cat > "$SMALL_INPUT" <<'JSON'
{"schema_version":1,"project_dir":"PROJECT_PLACEHOLDER","items":[
 {"path":"src/a.ts","change":"modified","old_path":"","selected":true,"insertions":1,"deletions":0},
 {"path":"src/b.ts","change":"modified","old_path":"","selected":true,"insertions":1,"deletions":0},
 {"path":"src/c.ts","change":"modified","old_path":"","selected":true,"insertions":1,"deletions":0}
]}
JSON
PG_PROJECT="$PROJECT_DIR" perl -0pi -e 's/PROJECT_PLACEHOLDER/$ENV{PG_PROJECT}/g' "$SMALL_INPUT"
"$SCRIPT" "$PROJECT_DIR" "$SMALL_INPUT" "$SMALL_OUTPUT"
test ! -s "$SMALL_OUTPUT"

echo "PASS: core prepare-semantic-groups"
