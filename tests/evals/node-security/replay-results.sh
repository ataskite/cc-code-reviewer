#!/bin/bash
set -euo pipefail

# Rebuild the deterministic controls for each committed fixture and re-check
# the saved model report. This does not re-run the model or claim fresh recall.
EVAL_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$EVAL_DIR/../../.." && pwd)"
RESULTS_DIR="$EVAL_DIR/results/2026-09-24"
WORK_PARENT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --results-dir) [ "$#" -ge 2 ] || { echo 'missing --results-dir value' >&2; exit 2; }; RESULTS_DIR="$2"; shift 2 ;;
    --work-dir) [ "$#" -ge 2 ] || { echo 'missing --work-dir value' >&2; exit 2; }; WORK_PARENT="$2"; shift 2 ;;
    *) echo "usage: replay-results.sh [--results-dir DIR] [--work-dir DIR]" >&2; exit 2 ;;
  esac
done
[ -d "$RESULTS_DIR" ] || { echo "results directory not found: $RESULTS_DIR" >&2; exit 2; }
EXPECTED_JSON="$RESULTS_DIR/baseline/expected-controls.json"
CATALOG_JSON="$RESULTS_DIR/baseline/catalog/node-security-controls.json"
[ -f "$EXPECTED_JSON" ] && [ -f "$CATALOG_JSON" ] || {
  echo 'results must carry frozen baseline expectations and catalog; never replay old reports against new controls' >&2
  exit 2
}
export CC_CODE_REVIEWER_SECURITY_CATALOG="$CATALOG_JSON"

if [ -n "$WORK_PARENT" ]; then
  mkdir -p "$WORK_PARENT"
  WORK_DIR="$(mktemp -d "$WORK_PARENT/replay.XXXXXX")"
else
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cc-node-eval-replay.XXXXXX")"
  trap 'rm -rf "$WORK_DIR"' EXIT
fi

perl -MJSON::PP -0777 -e '
  my $a = decode_json(<>);
  ref($a) eq "ARRAY" or die "expected-controls.json must be an array\n";
  for my $e (@$a) {
    my $key = $e->{case} // die "case key missing\n";
    $key =~ m{\A[a-z0-9-]+/[a-z0-9-]+\z} or die "invalid case key: $key\n";
    print "$key\n";
  }
' "$EXPECTED_JSON" > "$WORK_DIR/cases.txt"
expected_count="$(wc -l < "$WORK_DIR/cases.txt" | tr -d ' ')"
[ "$expected_count" -gt 0 ] || { echo 'empty eval baseline' >&2; exit 2; }

pass=0
fail=0
while IFS= read -r case_key; do
  fixture="$EVAL_DIR/$case_key"
  slug="${case_key//\//-}"
  report="$RESULTS_DIR/$slug.md"
  [ -d "$fixture" ] || { echo "missing fixture: $case_key" >&2; exit 2; }
  [ -f "$report" ] || { echo "missing report: $report" >&2; exit 2; }
  case_dir="$WORK_DIR/$slug"
  mkdir -p "$case_dir"
  bash "$ROOT_DIR/scripts/languages/frontend/collect-source-files.sh" "$fixture" > "$case_dir/source-manifest.txt" 2> "$case_dir/collect.log"
  bash "$ROOT_DIR/scripts/core/prepare-review-input.sh" "$fixture" frontend full 0 \
    "$case_dir/source-manifest.txt" "$case_dir/review-input.json" > "$case_dir/input.log"
  if [ -f "$RESULTS_DIR/baseline/fixture-inputs.json" ]; then
    perl -MJSON::PP -e '
      sub load { open my $f,"<",$_[0] or die; local $/; decode_json(<$f>) }
      my ($baseline,$input,$key)=@ARGV;
      my $b=load($baseline); my $i=load($input);
      my $old=$b->{$key} // die "EVAL_FIXTURE_BASELINE_MISSING=$key\n";
      my %expected=map { $_->{path}=>$_->{sha256} } @$old;
      my %actual=map { $_->{path}=>$_->{fingerprint} } grep { $_->{selected} } @{$i->{items}};
      die "EVAL_FIXTURE_CHANGED=$key\n" unless keys(%expected)==keys(%actual);
      for my $p (keys %expected) {
        die "EVAL_FIXTURE_CHANGED=$key/$p\n" unless ($actual{$p}//"") eq $expected{$p};
      }
    ' "$RESULTS_DIR/baseline/fixture-inputs.json" "$case_dir/review-input.json" "$case_key"
  fi
  bash "$ROOT_DIR/scripts/core/resolve-security-controls.sh" "$fixture" auto \
    "$case_dir/review-input.json" "$case_dir/controls.json" > "$case_dir/resolve.log"
  if verdict="$(perl "$EVAL_DIR/compare-eval-report.pl" "$report" \
      "$EXPECTED_JSON" "$case_key" --controls "$case_dir/controls.json")"; then
    pass=$((pass + 1))
    printf '%s PASS\n' "$case_key"
  else
    fail=$((fail + 1))
    printf '%s FAIL %s\n' "$case_key" "$verdict"
  fi
done < "$WORK_DIR/cases.txt"

printf 'EVAL_REPORTS_OK=%s PASS=%s FAIL=%s\n' "$((pass + fail))" "$pass" "$fail"
if [ -n "$WORK_PARENT" ]; then printf 'EVAL_WORK_DIR=%s\n' "$WORK_DIR"; fi
[ "$fail" -eq 0 ] && [ "$pass" -eq "$expected_count" ]
