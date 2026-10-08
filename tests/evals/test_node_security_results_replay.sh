#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REPLAY="$ROOT_DIR/tests/evals/node-security/replay-results.sh"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cc-node-eval-replay.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Public replay entry point must regenerate controls from committed fixtures.
output="$(bash "$REPLAY" --work-dir "$TEMP_DIR/work dir")"
[[ "$output" == *"EVAL_REPORTS_OK=19 PASS=19 FAIL=0"* ]]

# A changed report must invalidate the corresponding case; this is evidence
# checking, not merely counting committed Markdown files.
cp -R "$ROOT_DIR/tests/evals/node-security/results/2026-09-24" "$TEMP_DIR/results"
perl -0pi -e 's/CCR-NODE-BFFHEADER-001/CCR-NODE-BFFHEADER-999/g' \
  "$TEMP_DIR/results/bff-header-forwarding-vulnerable.md"
if bash "$REPLAY" --results-dir "$TEMP_DIR/results" --work-dir "$TEMP_DIR/tampered work" \
    >"$TEMP_DIR/tampered.out" 2>&1; then
  echo 'tampered report unexpectedly passed replay' >&2
  exit 1
fi
grep -q 'FAIL=' "$TEMP_DIR/tampered.out"

# The four new controls have their own independently generated model evidence;
# do not mix this profile/run with the historical 19-case result.
new_output="$(bash "$REPLAY" --results-dir "$ROOT_DIR/tests/evals/node-security/results/2026-10-08" --work-dir "$TEMP_DIR/new run")"
[[ "$new_output" == *"EVAL_REPORTS_OK=11 PASS=11 FAIL=0"* ]]

# Strictly require external-evidence state on the unknown-topology case. A
# pending risk is not a confirmed false positive; fabricating a confirmed
# defect on that control must fail the replay comparison.
cp -R "$ROOT_DIR/tests/evals/node-security/results/2026-10-08" "$TEMP_DIR/new tampered"
perl -0pi -e 's/^### 待确认/### P1/m' "$TEMP_DIR/new tampered/proxy-trust-topology-unproven.md"
if bash "$REPLAY" --results-dir "$TEMP_DIR/new tampered" --work-dir "$TEMP_DIR/new tampered work" >"$TEMP_DIR/new tampered.out" 2>&1; then
  echo 'fabricated confirmed topology defect unexpectedly passed' >&2
  exit 1
fi
grep -q 'false_positives.*CCR-NODE-PROXYTRUST-001' "$TEMP_DIR/new tampered.out"
